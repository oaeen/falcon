package gateway

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/falcon-gateway/falcon/core/internal/access"
	"github.com/falcon-gateway/falcon/core/internal/plugin"
	"github.com/falcon-gateway/falcon/core/internal/provider"
	"github.com/falcon-gateway/falcon/core/internal/redact"
	"github.com/falcon-gateway/falcon/core/internal/router"
	"github.com/falcon-gateway/falcon/core/internal/store"
	"github.com/falcon-gateway/falcon/core/internal/translate"
	"github.com/falcon-gateway/falcon/core/internal/types"
)

// Server implements the multi-protocol AI gateway HTTP server with hot Relisten().
type Server struct {
	mu         sync.Mutex
	store      *store.Store
	router     *router.Router
	plugins    *plugin.Manager
	httpClient *http.Client

	ln         net.Listener
	httpSrv    *http.Server
	listenAddr string
	port       int
	running    bool
}

// New creates a new Gateway Server.
func New(st *store.Store, rt *router.Router, pm *plugin.Manager, client *http.Client) *Server {
	if client == nil {
		client = &http.Client{Timeout: 5 * time.Minute}
	}
	return &Server{
		store:      st,
		router:     rt,
		plugins:    pm,
		httpClient: client,
	}
}

// Start binds the initial listener using current settings.
func (s *Server) Start() error {
	return s.Relisten()
}

// Relisten swaps the TCP listener cleanly whenever port or lanEnabled changes.
func (s *Server) Relisten() error {
	settings := s.store.Settings()
	host := "127.0.0.1"
	if settings.LanEnabled {
		host = "0.0.0.0"
	}
	addr := fmt.Sprintf("%s:%d", host, settings.Port)

	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return fmt.Errorf("listen %s: %w", addr, err)
	}
	actualPort := ln.Addr().(*net.TCPAddr).Port

	srv := &http.Server{
		Handler:           s.handler(),
		ReadHeaderTimeout: 30 * time.Second,
	}

	s.mu.Lock()
	oldSrv := s.httpSrv
	oldLn := s.ln
	s.ln = ln
	s.httpSrv = srv
	s.listenAddr = ln.Addr().String()
	s.port = actualPort
	s.running = true
	s.mu.Unlock()

	if oldSrv != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		_ = oldSrv.Shutdown(ctx)
		cancel()
	} else if oldLn != nil {
		_ = oldLn.Close()
	}

	go func() {
		err := srv.Serve(ln)
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			s.mu.Lock()
			if s.httpSrv == srv {
				s.running = false
			}
			s.mu.Unlock()
		}
	}()

	return nil
}

// Stop gracefully shuts down the gateway HTTP listener.
func (s *Server) Stop(ctx context.Context) error {
	s.mu.Lock()
	srv := s.httpSrv
	s.httpSrv = nil
	s.ln = nil
	s.running = false
	s.mu.Unlock()
	if srv != nil {
		return srv.Shutdown(ctx)
	}
	return nil
}

// Status returns the current runtime GatewayStatus snapshot.
func (s *Server) Status() types.GatewayStatus {
	s.mu.Lock()
	running := s.running
	listenAddr := s.listenAddr
	port := s.port
	s.mu.Unlock()

	cfg := s.store.ConfigSnapshot()
	if port == 0 {
		port = cfg.Settings.Port
	}

	var lanUrls []string
	if cfg.Settings.LanEnabled {
		for _, ip := range EnumerateLANIPv4() {
			lanUrls = append(lanUrls, fmt.Sprintf("http://%s:%d", ip, port))
		}
	}
	if lanUrls == nil {
		lanUrls = []string{}
	}

	modelCount := 0
	activeProviders := 0
	for _, p := range cfg.Providers {
		if p.Enabled {
			activeProviders++
			modelCount += len(p.ActiveModels())
		}
	}
	if s.plugins != nil {
		for _, pl := range s.plugins.StatePlugins() {
			if !pl.Enabled {
				continue
			}
			for _, pp := range pl.Providers {
				if len(pp.Accounts) > 0 || pp.ID == "opencode-zen-free" {
					activeProviders++
				}
				modelCount += len(pp.Models)
			}
		}
	}

	rtMode := "embedded"
	if s.plugins != nil {
		rtMode = s.plugins.RuntimeMode()
	}

	return types.GatewayStatus{
		Running:             running,
		ListenAddr:          listenAddr,
		Port:                port,
		LanEnabled:          cfg.Settings.LanEnabled,
		AllowLocalKeyless:   cfg.Settings.AllowLocalKeyless,
		LanUrls:             lanUrls,
		LoopbackUrl:         fmt.Sprintf("http://127.0.0.1:%d", port),
		UptimeSec:           s.store.UptimeSec(),
		ModelCount:          modelCount,
		ActiveProviderCount: activeProviders,
		PluginRuntimeMode:   rtMode,
	}
}

// EnumerateLANIPv4 returns sorted active non-loopback IPv4 addresses on local interfaces.
func EnumerateLANIPv4() []string {
	ifaces, err := net.Interfaces()
	if err != nil {
		return nil
	}
	var ips []string
	seen := make(map[string]bool)
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, addr := range addrs {
			var ip net.IP
			switch v := addr.(type) {
			case *net.IPNet:
				ip = v.IP
			case *net.IPAddr:
				ip = v.IP
			}
			if ip == nil || ip.IsLoopback() || ip.IsLinkLocalUnicast() {
				continue
			}
			v4 := ip.To4()
			if v4 == nil {
				continue
			}
			s := v4.String()
			if !seen[s] {
				seen[s] = true
				ips = append(ips, s)
			}
		}
	}
	sort.Strings(ips)
	return ips
}

func (s *Server) handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		settings := s.store.Settings()
		if access.ApplyCORS(w, r, settings.CorsOrigins) {
			return
		}

		path := r.URL.Path
		if path == "/health" && r.Method == http.MethodGet {
			writeJSON(w, http.StatusOK, map[string]any{
				"ok":        true,
				"status":    "running",
				"uptimeSec": s.store.UptimeSec(),
			})
			return
		}

		id, status, errMsg := access.Authenticate(r, s.store, settings)
		if status != 0 {
			access.WriteError(w, status, errMsg)
			return
		}

		switch {
		case path == "/v1/models" && r.Method == http.MethodGet:
			s.handleListModels(w, id)
		case path == "/api/tags" && r.Method == http.MethodGet:
			s.handleOllamaTags(w, id)
		case path == "/v1/chat/completions" && r.Method == http.MethodPost:
			s.handleCompletion(w, r, id, settings, types.ProtocolOpenAI, "")
		case path == "/v1/responses" && r.Method == http.MethodPost:
			s.handleCompletion(w, r, id, settings, types.ProtocolResponses, "")
		case path == "/v1/messages" && r.Method == http.MethodPost:
			s.handleCompletion(w, r, id, settings, types.ProtocolAnthropic, "")
		case path == "/v1/messages/count_tokens" && r.Method == http.MethodPost:
			s.handleCountTokens(w, r)
		case strings.HasPrefix(path, "/v1beta/models/") && r.Method == http.MethodPost:
			s.handleGeminiRoute(w, r, id, settings)
		case path == "/api/chat" && r.Method == http.MethodPost:
			s.handleCompletion(w, r, id, settings, types.ProtocolOllama, "")
		default:
			access.WriteError(w, http.StatusNotFound, "Unsupported gateway route: "+path)
		}
	})
}

func (s *Server) collectModels(id access.Identity) []string {
	cfg := s.store.ConfigSnapshot()
	seen := make(map[string]bool)
	var models []string
	add := func(m string) {
		if m != "" && !seen[m] && access.ModelAllowed(id, m) {
			seen[m] = true
			models = append(models, m)
		}
	}
	for _, g := range cfg.Groups {
		if g.Enabled {
			add(g.Name)
		}
	}
	for alias := range cfg.Aliases {
		add(alias)
	}
	for _, p := range cfg.Providers {
		if !p.Enabled {
			continue
		}
		for _, m := range p.ActiveModels() {
			add(p.ID + "/" + m)
		}
	}
	if s.plugins != nil {
		for _, pm := range s.plugins.AllModels() {
			add(pm.ID)
		}
	}
	sort.Strings(models)
	return models
}

func (s *Server) handleListModels(w http.ResponseWriter, id access.Identity) {
	models := s.collectModels(id)
	data := make([]map[string]any, 0, len(models))
	now := time.Now().Unix()
	for _, m := range models {
		ownedBy := "falcon"
		if prov, _, ok := strings.Cut(m, "/"); ok {
			ownedBy = prov
		}
		data = append(data, map[string]any{
			"id":       m,
			"object":   "model",
			"created":  now,
			"owned_by": ownedBy,
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"object": "list",
		"data":   data,
	})
}

func (s *Server) handleOllamaTags(w http.ResponseWriter, id access.Identity) {
	models := s.collectModels(id)
	out := make([]map[string]any, 0, len(models))
	for _, m := range models {
		out = append(out, map[string]any{
			"name":  m,
			"model": m,
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"models": out})
}

func (s *Server) handleCountTokens(w http.ResponseWriter, r *http.Request) {
	raw, err := io.ReadAll(io.LimitReader(r.Body, 8<<20))
	if err != nil {
		access.WriteError(w, http.StatusBadRequest, "Failed to read request body")
		return
	}
	// Approximate tokens (~4 chars/token) cleanly
	tokens := max(1, len(raw)/4)
	writeJSON(w, http.StatusOK, map[string]any{"input_tokens": tokens})
}

func (s *Server) handleGeminiRoute(w http.ResponseWriter, r *http.Request, id access.Identity, settings types.Settings) {
	rest := strings.TrimPrefix(r.URL.Path, "/v1beta/models/")
	modelPart, action, hasAction := strings.Cut(rest, ":")
	if !hasAction || modelPart == "" {
		access.WriteError(w, http.StatusBadRequest, "Invalid Gemini model path")
		return
	}
	s.handleCompletion(w, r, id, settings, types.ProtocolGemini, modelPart+":"+action)
}

func (s *Server) handleCompletion(w http.ResponseWriter, r *http.Request, id access.Identity, settings types.Settings, clientProto types.Protocol, geminiPathInfo string) {
	startTime := time.Now()
	rawBody, err := io.ReadAll(io.LimitReader(r.Body, 32<<20))
	if err != nil {
		access.WriteError(w, http.StatusBadRequest, "Failed to read request body")
		return
	}

	var modelHint string
	streamRequested := false
	if clientProto == types.ProtocolGemini && geminiPathInfo != "" {
		m, act, _ := strings.Cut(geminiPathInfo, ":")
		modelHint = m
		if strings.Contains(act, "stream") || r.URL.Query().Get("alt") == "sse" {
			streamRequested = true
		}
	}

	var probe map[string]any
	if err := json.Unmarshal(rawBody, &probe); err != nil {
		access.WriteError(w, http.StatusBadRequest, "Invalid JSON request body")
		return
	}
	if m, ok := probe["model"].(string); ok && strings.TrimSpace(m) != "" {
		modelHint = strings.TrimSpace(m)
	}
	if st, ok := probe["stream"].(bool); ok {
		streamRequested = st
	}

	if modelHint == "" {
		access.WriteError(w, http.StatusBadRequest, "Missing model field")
		return
	}
	if !access.ModelAllowed(id, modelHint) {
		access.WriteError(w, http.StatusForbidden, "Model not permitted for this access key")
		return
	}

	cfg := s.store.ConfigSnapshot()
	var pluginLookup router.PluginProviderLookup
	if s.plugins != nil {
		pluginLookup = s.plugins
	}
	targets := s.router.Resolve(cfg, pluginLookup, modelHint)
	if len(targets) == 0 {
		s.recordLog(id, clientProto, r.URL.Path, modelHint, "", "", http.StatusNotFound, 0, time.Since(startTime).Milliseconds(), translate.Usage{}, nil, nil, "No enabled provider or route for model: "+modelHint)
		access.WriteError(w, http.StatusNotFound, "No enabled provider or route for model: "+modelHint)
		return
	}

	// Outbound redaction
	redactSess := redact.NewSession(settings)
	maskedBody := redactSess.MaskJSON(rawBody)

	var canonReq *translate.CanonicalRequest
	var attempts []types.AttemptLog
	var lastStatus int
	var lastErr string

	for _, target := range targets {
		if target.IsPlugin {
			if err := s.tryPluginTarget(w, r, id, settings, clientProto, modelHint, target, maskedBody, rawBody, streamRequested, startTime, redactSess, &canonReq, &attempts, &lastStatus, &lastErr); err == nil {
				return
			}
			continue
		}

		prov, ok := s.store.GetProvider(target.ProviderID)
		if !ok || !prov.Enabled {
			continue
		}
		if err := s.tryProviderTarget(w, r, id, settings, clientProto, modelHint, target, prov, maskedBody, rawBody, streamRequested, startTime, redactSess, &canonReq, &attempts, &lastStatus, &lastErr); err == nil {
			return
		}
	}

	if lastStatus == 0 {
		lastStatus = http.StatusBadGateway
	}
	if lastErr == "" {
		lastErr = "All upstream targets failed"
	}
	s.recordLog(id, clientProto, r.URL.Path, modelHint, "", "", lastStatus, 0, time.Since(startTime).Milliseconds(), translate.Usage{}, redactSess, attempts, lastErr)
	access.WriteError(w, lastStatus, lastErr)
}

func (s *Server) buildUpstreamBody(clientProto, targetProto types.Protocol, targetModel string, streamRequested bool, maskedBody []byte, canonCache **translate.CanonicalRequest) ([]byte, error) {
	if clientProto == targetProto {
		return translate.RewriteModelJSON(maskedBody, targetModel), nil
	}
	if *canonCache == nil {
		c, err := translate.DecodeRequest(clientProto, targetModel, maskedBody)
		if err != nil {
			return nil, err
		}
		c.Stream = streamRequested
		*canonCache = c
	}
	cp := **canonCache
	cp.Model = targetModel
	cp.Stream = streamRequested
	return translate.EncodeRequest(targetProto, &cp)
}

func (s *Server) tryProviderTarget(
	w http.ResponseWriter,
	r *http.Request,
	id access.Identity,
	settings types.Settings,
	clientProto types.Protocol,
	requestedModel string,
	target router.Target,
	prov types.Provider,
	maskedBody []byte,
	_ []byte,
	streamRequested bool,
	startTime time.Time,
	redactSess *redact.Session,
	canonCache **translate.CanonicalRequest,
	attempts *[]types.AttemptLog,
	lastStatus *int,
	lastErr *string,
) error {
	upBody, err := s.buildUpstreamBody(clientProto, prov.Protocol, target.ModelID, streamRequested, maskedBody, canonCache)
	if err != nil {
		*lastStatus = http.StatusBadRequest
		*lastErr = err.Error()
		return err
	}

	base := strings.TrimRight(prov.BaseURL, "/")
	if base == "" {
		if preset, ok := provider.FindPreset(prov.Preset); ok {
			base = preset.BaseURL
		}
	}
	relPath := translate.UpstreamPath(prov.Protocol, target.ModelID, streamRequested)
	targetURL := provider.BuildUpstreamURL(base, relPath)

	skipKeys := make(map[string]bool)
	maxKeyTries := max(1, len(prov.Keys))
	for kTry := 0; kTry < maxKeyTries; kTry++ {
		var secret string
		var keyID string
		if len(prov.Keys) > 0 {
			pk, ok := provider.PickKey(prov, skipKeys)
			if !ok {
				break
			}
			secret = pk.Secret
			keyID = pk.ID
		} else if prov.Protocol != types.ProtocolOllama {
			break
		}

		reqStart := time.Now()
		upReq, err := http.NewRequestWithContext(r.Context(), http.MethodPost, targetURL, bytes.NewReader(upBody))
		if err != nil {
			*lastErr = err.Error()
			return err
		}
		upReq.Header.Set("Content-Type", "application/json")
		if streamRequested {
			upReq.Header.Set("Accept", "text/event-stream")
		}
		provider.ApplyUpstreamAuth(upReq, prov.Protocol, secret)

		resp, err := s.httpClient.Do(upReq)
		lat := time.Since(reqStart).Milliseconds()
		if err != nil {
			*attempts = append(*attempts, types.AttemptLog{Target: target.Raw, StatusCode: 0, LatencyMs: lat, Error: err.Error()})
			*lastStatus = http.StatusBadGateway
			*lastErr = err.Error()
			s.router.RecordFailure(target.Raw, 0)
			return err
		}

		if resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode >= 500 {
			errBytes, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
			resp.Body.Close()
			msg := strings.TrimSpace(string(errBytes))
			*attempts = append(*attempts, types.AttemptLog{Target: target.Raw, StatusCode: resp.StatusCode, LatencyMs: lat, Error: msg})
			*lastStatus = resp.StatusCode
			*lastErr = fmt.Sprintf("upstream %s HTTP %d: %s", target.Raw, resp.StatusCode, msg)
			if keyID != "" && (resp.StatusCode == 401 || resp.StatusCode == 429) {
				skipKeys[keyID] = true
				continue
			}
			s.router.RecordFailure(target.Raw, resp.StatusCode)
			return errors.New(*lastErr)
		}

		if resp.StatusCode >= 400 {
			errBytes, _ := io.ReadAll(io.LimitReader(resp.Body, 64*1024))
			resp.Body.Close()
			*attempts = append(*attempts, types.AttemptLog{Target: target.Raw, StatusCode: resp.StatusCode, LatencyMs: lat, Error: string(errBytes)})
			s.recordLog(id, clientProto, r.URL.Path, requestedModel, target.ProviderID, target.ModelID, resp.StatusCode, lat, time.Since(startTime).Milliseconds(), translate.Usage{}, redactSess, *attempts, string(errBytes))
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(resp.StatusCode)
			_, _ = w.Write(errBytes)
			return nil
		}

		*attempts = append(*attempts, types.AttemptLog{Target: target.Raw, StatusCode: resp.StatusCode, LatencyMs: lat})
		s.relaySuccessResponse(w, r, id, settings, clientProto, prov.Protocol, requestedModel, target, resp, streamRequested, startTime, redactSess, *attempts)
		return nil
	}

	return errors.New("no valid upstream key succeeded")
}

func (s *Server) tryPluginTarget(
	w http.ResponseWriter,
	r *http.Request,
	id access.Identity,
	settings types.Settings,
	clientProto types.Protocol,
	requestedModel string,
	target router.Target,
	maskedBody []byte,
	_ []byte,
	streamRequested bool,
	startTime time.Time,
	redactSess *redact.Session,
	canonCache **translate.CanonicalRequest,
	attempts *[]types.AttemptLog,
	lastStatus *int,
	lastErr *string,
) error {
	if s.plugins == nil {
		return errors.New("plugin manager unavailable")
	}
	minfo, _ := s.plugins.ModelInfo(target.ProviderID, target.ModelID)
	targetProto := minfo.Protocol
	if targetProto == "" {
		targetProto = types.ProtocolOpenAI
	}
	apiModel := minfo.APIID
	if apiModel == "" {
		apiModel = target.ModelID
	}

	upBody, err := s.buildUpstreamBody(clientProto, targetProto, apiModel, streamRequested, maskedBody, canonCache)
	if err != nil {
		*lastStatus = http.StatusBadRequest
		*lastErr = err.Error()
		return err
	}

	reqStart := time.Now()
	hdrs := map[string]string{"content-type": "application/json"}
	if streamRequested {
		hdrs["accept"] = "text/event-stream"
	}
	resp, actualProto, err := s.plugins.ExecuteRequest(r.Context(), target.ProviderID, target.ModelID, streamRequested, upBody, hdrs)
	lat := time.Since(reqStart).Milliseconds()
	if err != nil {
		*attempts = append(*attempts, types.AttemptLog{Target: target.Raw, StatusCode: 0, LatencyMs: lat, Error: err.Error()})
		*lastStatus = http.StatusBadGateway
		*lastErr = err.Error()
		s.router.RecordFailure(target.Raw, 0)
		return err
	}
	if resp.StatusCode == 429 || resp.StatusCode >= 500 {
		errBytes, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		resp.Body.Close()
		*attempts = append(*attempts, types.AttemptLog{Target: target.Raw, StatusCode: resp.StatusCode, LatencyMs: lat, Error: string(errBytes)})
		*lastStatus = resp.StatusCode
		*lastErr = fmt.Sprintf("plugin %s HTTP %d: %s", target.Raw, resp.StatusCode, string(errBytes))
		s.router.RecordFailure(target.Raw, resp.StatusCode)
		return errors.New(*lastErr)
	}
	if resp.StatusCode >= 400 {
		errBytes, _ := io.ReadAll(io.LimitReader(resp.Body, 64*1024))
		resp.Body.Close()
		*attempts = append(*attempts, types.AttemptLog{Target: target.Raw, StatusCode: resp.StatusCode, LatencyMs: lat, Error: string(errBytes)})
		s.recordLog(id, clientProto, r.URL.Path, requestedModel, target.ProviderID, target.ModelID, resp.StatusCode, lat, time.Since(startTime).Milliseconds(), translate.Usage{}, redactSess, *attempts, string(errBytes))
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(resp.StatusCode)
		_, _ = w.Write(errBytes)
		return nil
	}

	*attempts = append(*attempts, types.AttemptLog{Target: target.Raw, StatusCode: resp.StatusCode, LatencyMs: lat})
	s.relaySuccessResponse(w, r, id, settings, clientProto, actualProto, requestedModel, target, resp, streamRequested, startTime, redactSess, *attempts)
	return nil
}

func (s *Server) relaySuccessResponse(
	w http.ResponseWriter,
	r *http.Request,
	id access.Identity,
	settings types.Settings,
	clientProto types.Protocol,
	targetProto types.Protocol,
	requestedModel string,
	target router.Target,
	resp *http.Response,
	streamRequested bool,
	startTime time.Time,
	redactSess *redact.Session,
	attempts []types.AttemptLog,
) {
	defer resp.Body.Close()

	ct := resp.Header.Get("Content-Type")
	isStream := streamRequested || strings.Contains(strings.ToLower(ct), "text/event-stream") || strings.Contains(strings.ToLower(ct), "ndjson")

	if !isStream {
		rawResp, err := io.ReadAll(io.LimitReader(resp.Body, 16<<20))
		lat := time.Since(startTime).Milliseconds()
		if err != nil {
			access.WriteError(w, http.StatusBadGateway, err.Error())
			return
		}
		var outBytes []byte
		var usage translate.Usage
		if clientProto == targetProto {
			outBytes = rawResp
			usage = translate.ExtractUsageFromJSON(targetProto, rawResp)
		} else {
			canon, derr := translate.DecodeResponse(targetProto, rawResp)
			if derr != nil {
				outBytes = rawResp
			} else {
				canon.Model = requestedModel
				usage = canon.Usage
				enc, eerr := translate.EncodeResponse(clientProto, canon)
				if eerr != nil {
					outBytes = rawResp
				} else {
					outBytes = enc
				}
			}
		}
		if settings.RedactRestore && redactSess.TotalHits() > 0 {
			outBytes = redactSess.RestoreJSON(outBytes)
		}
		s.router.RecordTTFT(target.Raw, lat)
		s.recordLog(id, clientProto, r.URL.Path, requestedModel, target.ProviderID, target.ModelID, resp.StatusCode, lat, lat, usage, redactSess, attempts, "")
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(resp.StatusCode)
		_, _ = w.Write(outBytes)
		return
	}

	// Streaming response
	if clientProto == types.ProtocolOllama {
		w.Header().Set("Content-Type", "application/x-ndjson")
	} else {
		w.Header().Set("Content-Type", "text/event-stream; charset=utf-8")
	}
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("X-Accel-Buffering", "no")
	w.WriteHeader(resp.StatusCode)
	flusher, _ := w.(http.Flusher)

	var translator *translate.StreamTranslator
	var sniffer *translate.UsageSniffer
	if clientProto != targetProto {
		translator = translate.NewStreamTranslator(targetProto, clientProto, requestedModel)
	} else {
		sniffer = translate.NewUsageSniffer(targetProto)
	}
	var restorer *redact.StreamRestorer
	if settings.RedactRestore && redactSess.TotalHits() > 0 {
		restorer = redact.NewStreamRestorer(redactSess)
	}

	var ttftMs int64
	buf := make([]byte, 8192)
	for {
		n, readErr := resp.Body.Read(buf)
		if n > 0 {
			chunk := buf[:n]
			if translator != nil {
				chunk = translator.ProcessChunk(chunk)
			} else if sniffer != nil {
				sniffer.Feed(chunk)
			}
			if restorer != nil && len(chunk) > 0 {
				chunk = restorer.ProcessChunk(chunk)
			}
			if len(chunk) > 0 {
				if ttftMs == 0 {
					ttftMs = max(1, time.Since(startTime).Milliseconds())
					s.router.RecordTTFT(target.Raw, ttftMs)
				}
				_, _ = w.Write(chunk)
				if flusher != nil {
					flusher.Flush()
				}
			}
		}
		if readErr != nil {
			break
		}
	}

	if translator != nil {
		tail := translator.Flush()
		if restorer != nil && len(tail) > 0 {
			tail = restorer.ProcessChunk(tail)
		}
		if len(tail) > 0 {
			_, _ = w.Write(tail)
		}
	}
	if restorer != nil {
		if tail := restorer.Flush(); len(tail) > 0 {
			_, _ = w.Write(tail)
		}
	}
	if flusher != nil {
		flusher.Flush()
	}

	var usage translate.Usage
	if translator != nil {
		usage = translator.Usage
	} else if sniffer != nil {
		usage = sniffer.Usage
	}
	totalLat := time.Since(startTime).Milliseconds()
	if ttftMs == 0 {
		ttftMs = totalLat
	}
	s.recordLog(id, clientProto, r.URL.Path, requestedModel, target.ProviderID, target.ModelID, resp.StatusCode, ttftMs, totalLat, usage, redactSess, attempts, "")
}

func (s *Server) recordLog(
	id access.Identity,
	proto types.Protocol,
	path string,
	reqModel string,
	upProv string,
	upModel string,
	status int,
	ttftMs int64,
	latMs int64,
	usage translate.Usage,
	redactSess *redact.Session,
	attempts []types.AttemptLog,
	errMsg string,
) {
	var hitsByKind map[string]int
	redactedCount := 0
	if redactSess != nil {
		hitsByKind = redactSess.HitsByKind()
		redactedCount = redactSess.TotalHits()
	}
	estUsd := float64(usage.InputTokens)*0.000001 + float64(usage.OutputTokens)*0.000003
	s.store.RecordRequest(types.RequestLogEntry{
		ClientIP:         id.Peer.IP,
		ClientKind:       id.Peer.Kind,
		KeyID:            id.KeyID,
		KeyName:          id.KeyName,
		Protocol:         proto,
		Path:             path,
		RequestedModel:   reqModel,
		UpstreamProvider: upProv,
		UpstreamModel:    upModel,
		StatusCode:       status,
		TtftMs:           ttftMs,
		LatencyMs:        latMs,
		InputTokens:      usage.InputTokens,
		OutputTokens:     usage.OutputTokens,
		EstimatedUsd:     estUsd,
		RedactedCount:    redactedCount,
		Attempts:         attempts,
		Error:            errMsg,
	}, hitsByKind)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
