package plugin

import (
	"bufio"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
)

const (
	frameOverhead       = 2048
	defaultStreamWindow = 512 << 10
)

// BunHost manages the long-lived Bun child process executing embedded host.mjs.
type BunHost struct {
	mu       sync.Mutex
	bunPath  string
	dataDir  string
	cacheDir string
	caBundle string
	dns      string

	cmd     *exec.Cmd
	stdin   io.WriteCloser
	writeMu sync.Mutex
	nextID  atomic.Int64

	pendingMu sync.Mutex
	pending   map[int64]*rpcPending
	onEvent   func(event map[string]any)
}

type rpcPending struct {
	done   chan rpcReply
	stream *streamState
}

type rpcReply struct {
	result json.RawMessage
	err    error
}

type streamState struct {
	headReady chan struct{}
	status    int
	headers   http.Header
	pr        *io.PipeReader
	pw        *io.PipeWriter
	errOnce   sync.Once
	err       error
}

// DetectBun finds a usable Bun binary from configuredPath or PATH. Returns "" on iOS,
// when configuredPath disables Bun ("embedded", "none", "off"), or if missing.
func DetectBun(configuredPath string) string {
	if runtime.GOOS == "ios" {
		return ""
	}
	tryPath := func(p string) string {
		p = strings.TrimSpace(p)
		if p == "" {
			return ""
		}
		if fi, err := os.Stat(p); err != nil || fi.IsDir() {
			return ""
		}
		if err := exec.Command(p, "--version").Run(); err != nil {
			return ""
		}
		return p
	}
	trimmed := strings.TrimSpace(configuredPath)
	switch strings.ToLower(trimmed) {
	case "embedded", "none", "off", "false", "0":
		return ""
	}
	if trimmed != "" && trimmed != "bun" {
		return tryPath(trimmed)
	}
	if p, err := exec.LookPath("bun"); err == nil {
		if ok := tryPath(p); ok != "" {
			return ok
		}
	}
	return ""
}

func NewBunHost(bunPath, dataDir, cacheDir, caBundle, dnsServers string, onEvent func(map[string]any)) *BunHost {
	return &BunHost{
		bunPath:  bunPath,
		dataDir:  dataDir,
		cacheDir: cacheDir,
		caBundle: caBundle,
		dns:      dnsServers,
		pending:  make(map[int64]*rpcPending),
		onEvent:  onEvent,
	}
}

func (h *BunHost) IsRunning() bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.cmd != nil && h.cmd.Process != nil
}

func (h *BunHost) Stop() {
	h.mu.Lock()
	cmd := h.cmd
	stdin := h.stdin
	h.cmd = nil
	h.stdin = nil
	h.mu.Unlock()

	if stdin != nil {
		_ = stdin.Close()
	}
	if cmd != nil && cmd.Process != nil {
		_ = cmd.Process.Kill()
		_ = cmd.Wait()
	}
	h.failAllPending(errors.New("plugin host stopped"))
}

func (h *BunHost) failAllPending(err error) {
	h.pendingMu.Lock()
	all := h.pending
	h.pending = make(map[int64]*rpcPending)
	h.pendingMu.Unlock()

	for _, p := range all {
		if p.stream != nil {
			p.stream.errOnce.Do(func() {
				p.stream.err = err
				close(p.stream.headReady)
			})
			_ = p.stream.pw.CloseWithError(err)
		}
		select {
		case p.done <- rpcReply{err: err}:
		default:
		}
	}
}

func (h *BunHost) StartAndInit(ctx context.Context, plugins []map[string]any, options map[string]map[string]bool) ([]map[string]any, error) {
	h.Stop()

	if h.bunPath == "" {
		return nil, errors.New("bun binary unavailable")
	}
	if err := os.MkdirAll(h.dataDir, 0o700); err != nil {
		return nil, err
	}
	hostPath := filepath.Join(h.dataDir, "host.mjs")
	if err := os.WriteFile(hostPath, embeddedHostMJS, 0o644); err != nil {
		return nil, err
	}

	cmd := exec.Command(h.bunPath, "run", hostPath)
	cmd.Dir = h.dataDir
	env := append([]string{}, os.Environ()...)
	env = append(env, "NODE_USE_SYSTEM_CA=1")
	if h.caBundle != "" {
		env = append(env, "SSL_CERT_FILE="+h.caBundle, "NODE_EXTRA_CA_CERTS="+h.caBundle)
	}
	if h.dns != "" {
		env = append(env, "FALCON_DNS="+h.dns)
	}
	cmd.Env = env

	stdin, err := cmd.StdinPipe()
	if err != nil {
		return nil, err
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return nil, err
	}

	if err := cmd.Start(); err != nil {
		return nil, err
	}

	h.mu.Lock()
	h.cmd = cmd
	h.stdin = stdin
	h.mu.Unlock()

	go h.readStdout(stdout)
	go h.drainStderr(stderr)
	go func() {
		_ = cmd.Wait()
		h.mu.Lock()
		if h.cmd == cmd {
			h.cmd = nil
			h.stdin = nil
		}
		h.mu.Unlock()
		h.failAllPending(errors.New("plugin host exited"))
	}()

	var res struct {
		Plugins []map[string]any `json:"plugins"`
	}
	err = h.Call(ctx, "init", map[string]any{
		"authPath":  filepath.Join(h.dataDir, "plugin-auth.json"),
		"directory": h.dataDir,
		"options":   options,
		"plugins":   plugins,
	}, &res)
	if err != nil {
		h.Stop()
		return nil, err
	}
	return res.Plugins, nil
}

func (h *BunHost) drainStderr(r io.Reader) {
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 4096), 256*1024)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line != "" && h.onEvent != nil {
			h.onEvent(map[string]any{"event": "log", "level": "stderr", "message": line})
		}
	}
}

func (h *BunHost) readStdout(r io.Reader) {
	br := bufio.NewReaderSize(r, 64*1024)
	for {
		line, err := br.ReadBytes('\n')
		if len(line) > 0 {
			h.handleLine(line)
		}
		if err != nil {
			break
		}
	}
}

func (h *BunHost) handleLine(line []byte) {
	var msg struct {
		ID      *int64            `json:"id"`
		Event   string            `json:"event"`
		Status  int               `json:"status"`
		Headers map[string]string `json:"headers"`
		Data    string            `json:"data"`
		Result  json.RawMessage   `json:"result"`
		Error   *struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if json.Unmarshal(line, &msg) != nil {
		return
	}
	if msg.ID == nil {
		if h.onEvent != nil {
			var ev map[string]any
			if json.Unmarshal(line, &ev) == nil {
				h.onEvent(ev)
			}
		}
		return
	}
	id := *msg.ID
	h.pendingMu.Lock()
	p := h.pending[id]
	h.pendingMu.Unlock()
	if p == nil {
		return
	}

	if p.stream != nil {
		switch msg.Event {
		case "head":
			hdr := make(http.Header, len(msg.Headers))
			for k, v := range msg.Headers {
				hdr.Set(k, v)
			}
			p.stream.status = msg.Status
			p.stream.headers = hdr
			p.stream.errOnce.Do(func() {
				close(p.stream.headReady)
			})
			return
		case "chunk":
			raw, err := base64.StdEncoding.DecodeString(msg.Data)
			if err != nil {
				_ = p.stream.pw.CloseWithError(err)
				return
			}
			if len(raw) > 0 {
				if _, werr := p.stream.pw.Write(raw); werr != nil {
					return
				}
			}
			_ = h.writeJSON(map[string]any{
				"method": "credit",
				"params": map[string]any{"id": id, "n": len(raw) + frameOverhead},
			})
			return
		}
		h.pendingMu.Lock()
		delete(h.pending, id)
		h.pendingMu.Unlock()
		if msg.Error != nil {
			err := errors.New(msg.Error.Message)
			p.stream.errOnce.Do(func() {
				p.stream.err = err
				close(p.stream.headReady)
			})
			_ = p.stream.pw.CloseWithError(err)
		} else {
			p.stream.errOnce.Do(func() {
				close(p.stream.headReady)
			})
			_ = p.stream.pw.Close()
		}
		return
	}

	h.pendingMu.Lock()
	delete(h.pending, id)
	h.pendingMu.Unlock()
	if msg.Error != nil {
		p.done <- rpcReply{err: errors.New(msg.Error.Message)}
	} else {
		p.done <- rpcReply{result: msg.Result}
	}
}

func (h *BunHost) writeJSON(v any) error {
	b, err := json.Marshal(v)
	if err != nil {
		return err
	}
	b = append(b, '\n')
	h.writeMu.Lock()
	defer h.writeMu.Unlock()
	h.mu.Lock()
	stdin := h.stdin
	h.mu.Unlock()
	if stdin == nil {
		return errors.New("plugin host is not running")
	}
	_, err = stdin.Write(b)
	return err
}

func (h *BunHost) Call(ctx context.Context, method string, params any, out any) error {
	id := h.nextID.Add(1)
	p := &rpcPending{done: make(chan rpcReply, 1)}
	h.pendingMu.Lock()
	h.pending[id] = p
	h.pendingMu.Unlock()

	if err := h.writeJSON(map[string]any{
		"id":     id,
		"method": method,
		"params": params,
	}); err != nil {
		h.pendingMu.Lock()
		delete(h.pending, id)
		h.pendingMu.Unlock()
		return err
	}

	select {
	case rep := <-p.done:
		if rep.err != nil {
			return rep.err
		}
		if out != nil && len(rep.result) > 0 && string(rep.result) != "null" {
			return json.Unmarshal(rep.result, out)
		}
		return nil
	case <-ctx.Done():
		h.pendingMu.Lock()
		delete(h.pending, id)
		h.pendingMu.Unlock()
		_ = h.writeJSON(map[string]any{"method": "abort", "params": map[string]any{"id": id}})
		return ctx.Err()
	}
}

// Fetch executes a streaming HTTP request through a plugin's loader fetch and returns an *http.Response.
func (h *BunHost) Fetch(ctx context.Context, params map[string]any) (*http.Response, error) {
	id := h.nextID.Add(1)
	pr, pw := io.Pipe()
	ss := &streamState{
		headReady: make(chan struct{}),
		pr:        pr,
		pw:        pw,
	}
	p := &rpcPending{stream: ss}
	h.pendingMu.Lock()
	h.pending[id] = p
	h.pendingMu.Unlock()

	params["window"] = defaultStreamWindow
	if err := h.writeJSON(map[string]any{
		"id":     id,
		"method": "fetch",
		"params": params,
	}); err != nil {
		h.pendingMu.Lock()
		delete(h.pending, id)
		h.pendingMu.Unlock()
		_ = pw.Close()
		_ = pr.Close()
		return nil, err
	}

	go func() {
		<-ctx.Done()
		h.pendingMu.Lock()
		_, stillOpen := h.pending[id]
		if stillOpen {
			delete(h.pending, id)
		}
		h.pendingMu.Unlock()
		if stillOpen {
			_ = h.writeJSON(map[string]any{"method": "abort", "params": map[string]any{"id": id}})
			_ = pw.CloseWithError(ctx.Err())
		}
	}()

	select {
	case <-ss.headReady:
		if ss.err != nil {
			_ = pr.Close()
			return nil, ss.err
		}
		status := ss.status
		if status == 0 {
			status = 200
		}
		hdr := ss.headers
		if hdr == nil {
			hdr = http.Header{}
		}
		return &http.Response{
			StatusCode: status,
			Status:     fmt.Sprintf("%d %s", status, http.StatusText(status)),
			Header:     hdr,
			Body:       pr,
		}, nil
	case <-ctx.Done():
		_ = pr.Close()
		return nil, ctx.Err()
	}
}
