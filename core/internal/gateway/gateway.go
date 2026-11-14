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
	"github.com/falcon-gateway/falcon/core/internal/router"
	"github.com/falcon-gateway/falcon/core/internal/store"
	"github.com/falcon-gateway/falcon/core/internal/translate"
	"github.com/falcon-gateway/falcon/core/internal/types"
)

var streamBufPool = sync.Pool{
	New: func() any {
		b := make([]byte, 32*1024)
		return &b
	},
}

// Server implements the multi-protocol AI gateway HTTP server with hot Relisten().
type Server struct {
	relistenMu sync.Mutex
	mu         sync.Mutex
	store      *store.Store
	router     *router.Router
	plugins    *plugin.Manager
	httpClient *http.Client

	ln         net.Listener
	ln6        net.Listener
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

func listenWithRetry(addr string) (net.Listener, error) {
	var lastErr error
	for i := 0; i < 6; i++ {
		ln, err := net.Listen("tcp", addr)
		if err == nil {
			return ln, nil
		}
		lastErr = err
		if !strings.Contains(strings.ToLower(err.Error()), "address already in use") {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	return nil, lastErr
}

func (s *Server) bindAndServe(ln net.Listener, host string) {
	actualPort := ln.Addr().(*net.TCPAddr).Port
	var ln6 net.Listener
	if host == "127.0.0.1" {
		if l6, err := net.Listen("tcp6", fmt.Sprintf("[::1]:%d", actualPort)); err == nil {
			ln6 = l6
		}
	}
	srv := &http.Server{
		Handler:           s.handler(),
		ReadHeaderTimeout: 30 * time.Second,
	}

	s.mu.Lock()
	s.ln = ln
	s.ln6 = ln6
	s.httpSrv = srv
	s.listenAddr = fmt.Sprintf("%s:%d", host, actualPort)
	s.port = actualPort
	s.running = true
	s.mu.Unlock()

	if ln6 != nil {
		go func() {
			_ = srv.Serve(ln6)
		}()
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
}

// Relisten swaps the TCP listener cleanly whenever port or lanEnabled changes.
// It closes the prior listener BEFORE binding the new address so switching
// 127.0.0.1:<port> <-> 0.0.0.0:<port> succeeds on Linux/Android without EADDRINUSE.
func (s *Server) Relisten() error {
	s.relistenMu.Lock()
	defer s.relistenMu.Unlock()

	settings := s.store.Settings()
	host := "127.0.0.1"
	if settings.LanEnabled {
		host = "0.0.0.0"
	}
	addr := fmt.Sprintf("%s:%d", host, settings.Port)

	s.mu.Lock()
	if s.httpSrv != nil && s.ln != nil && s.running && s.listenAddr == addr {
		s.mu.Unlock()
		return nil
	}
	oldSrv := s.httpSrv
	oldLn := s.ln
	oldLn6 := s.ln6
	oldAddr := s.listenAddr
	oldHost := "127.0.0.1"
	if strings.HasPrefix(oldAddr, "0.0.0.0:") || strings.HasPrefix(oldAddr, "[::]:") {
		oldHost = "0.0.0.0"
	}
	wasRunning := s.running
	s.httpSrv = nil
	s.ln = nil
	s.ln6 = nil
	s.running = false
	s.mu.Unlock()

	// Release the existing listening sockets BEFORE binding the new address.
	if oldLn6 != nil {
		_ = oldLn6.Close()
	}
	if oldLn != nil {
		_ = oldLn.Close()
	}
	if oldSrv != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
		_ = oldSrv.Shutdown(ctx)
		cancel()
	}

	ln, err := listenWithRetry(addr)
	if err != nil {
		if wasRunning && oldAddr != "" {
			if rbLn, rbErr := listenWithRetry(oldAddr); rbErr == nil {
				s.bindAndServe(rbLn, oldHost)
			}
		}
		return fmt.Errorf("listen %s: %w", addr, err)
	}

	s.bindAndServe(ln, host)
	return nil
}

// Stop gracefully shuts down the gateway HTTP listener.
func (s *Server) Stop(ctx context.Context) error {
	s.mu.Lock()
	srv := s.httpSrv
	ln := s.ln
	ln6 := s.ln6
	s.httpSrv = nil
	s.ln = nil
	s.ln6 = nil
	s.running = false
	s.mu.Unlock()
	if ln6 != nil {
		_ = ln6.Close()
	}
	if ln != nil {
		_ = ln.Close()
	}
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
				if pp.IsCallable() {
					activeProviders++
					modelCount += len(pp.ActiveModels())
				}
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
		RequireAccessKey:    cfg.Settings.RequireAccessKey,
		AllowLocalKeyless:   cfg.Settings.AllowLocalKeyless,
		LanUrls:             lanUrls,
		LoopbackUrl:         fmt.Sprintf("http://127.0.0.1:%d", port),
		UptimeSec:           s.store.UptimeSec(),
		ModelCount:          modelCount,
		ActiveProviderCount: activeProviders,
		PluginRuntimeMode:   rtMode,
	}
}

type ifaceIP struct {
	name string
	ip   net.IP
}

var excludedIfacePrefixes = []string{"rmnet", "ccmni", "pdp_ip", "clat", "dummy"}

func isExcludedIfaceName(name string) bool {
	lower := strings.ToLower(strings.TrimSpace(name))
	for _, p := range excludedIfacePrefixes {
		if strings.HasPrefix(lower, p) {
			return true
		}
	}
	return false
}

func isFakeIPv4(v4 net.IP) bool {
	// RFC 2544 benchmark / Clash & Sing-box TUN fake-IP subnet 198.18.0.0/15
	return v4[0] == 198 && (v4[1] == 18 || v4[1] == 19)
}

func isRFC1918(v4 net.IP) bool {
	if v4[0] == 10 {
		return true
	}
	if v4[0] == 172 && v4[1] >= 16 && v4[1] <= 31 {
		return true
	}
	return v4[0] == 192 && v4[1] == 168
}

func filterAndSortLANIPs(entries []ifaceIP) []string {
	var rfc1918, other []string
	seen := make(map[string]bool)
	for _, ent := range entries {
		if isExcludedIfaceName(ent.name) {
			continue
		}
		if ent.ip == nil || ent.ip.IsLoopback() || ent.ip.IsLinkLocalUnicast() || ent.ip.IsLinkLocalMulticast() || ent.ip.IsUnspecified() || ent.ip.IsMulticast() {
			continue
		}
		v4 := ent.ip.To4()
		if v4 == nil || isFakeIPv4(v4) {
			continue
		}
		s := v4.String()
		if seen[s] {
			continue
		}
		seen[s] = true
		if isRFC1918(v4) {
			rfc1918 = append(rfc1918, s)
		} else {
			other = append(other, s)
		}
	}
	sort.Strings(rfc1918)
	sort.Strings(other)
	return append(rfc1918, other...)
}

// EnumerateLANIPv4 returns sorted active non-loopback IPv4 addresses on local interfaces,
// excluding fake-IP TUN ranges (198.18.0.0/15) and cellular/dummy interfaces, with RFC 1918 prioritized.
func EnumerateLANIPv4() []string {
	ifaces, err := net.Interfaces()
	if err != nil {
		return nil
	}
	var entries []ifaceIP
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 || isExcludedIfaceName(iface.Name) {
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
			entries = append(entries, ifaceIP{name: iface.Name, ip: ip})
		}
	}
	return filterAndSortLANIPs(entries)
}

// normalizeGatewayPath canonicalizes incoming paths so clients configured with or without
// a trailing /v1 (or accidentally doubling /v1/v1 or /v1beta/v1beta) all resolve cleanly.
func normalizeGatewayPath(rawPath string) string {
	p := rawPath
	for strings.Contains(p, "//") {
		p = strings.ReplaceAll(p, "//", "/")
	}
	if len(p) > 1 {
		p = strings.TrimRight(p, "/")
	}
	if p == "" {
		return "/"
	}
	for {
		switch {
		case strings.HasPrefix(p, "/v1/v1/") || p == "/v1/v1":
			p = strings.TrimPrefix(p, "/v1")
		case strings.HasPrefix(p, "/v1beta/v1beta/") || p == "/v1beta/v1beta":
			p = strings.TrimPrefix(p, "/v1beta")
		case strings.HasPrefix(p, "/v1/v1beta/") || p == "/v1/v1beta":
			p = strings.TrimPrefix(p, "/v1")
		case strings.HasPrefix(p, "/v1/api/") || p == "/v1/api":
			p = strings.TrimPrefix(p, "/v1")
		case p == "/v1/health":
			p = "/health"
		default:
			goto bareMap
		}
	}
bareMap:
	switch {
	case p == "/models":
		return "/v1/models"
	case strings.HasPrefix(p, "/models/"):
		return "/v1" + p
	case p == "/chat/completions", p == "/responses", p == "/messages", p == "/messages/count_tokens":
		return "/v1" + p
	default:
		return p
	}
}

func (s *Server) handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		settings := s.store.Settings()
		if access.ApplyCORS(w, r, settings.CorsOrigins) {
			return
		}

		normPath := normalizeGatewayPath(r.URL.Path)
		isGetOrHead := r.Method == http.MethodGet || r.Method == http.MethodHead

		if normPath == "/health" && isGetOrHead {
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
		case (normPath == "/" || normPath == "/v1") && isGetOrHead:
			writeJSON(w, http.StatusOK, map[string]any{
				"ok":        true,
				"service":   "falcon",
				"status":    "running",
				"uptimeSec": s.store.UptimeSec(),
				"endpoints": map[string]string{
					"models":            "/v1/models",
					"chatCompletions":   "/v1/chat/completions",
					"responses":         "/v1/responses",
					"anthropicMessages": "/v1/messages",
					"geminiModels":      "/v1beta/models",
					"ollamaTags":        "/api/tags",
				},
			})
		case normPath == "/v1/models" && isGetOrHead:
			s.handleListModels(w, id)
		case normPath == "/v1beta/models" && isGetOrHead:
			s.handleGeminiListModels(w, id)
		case normPath == "/api/tags" && isGetOrHead:
			s.handleOllamaTags(w, id)
		case normPath == "/api/version" && isGetOrHead:
			writeJSON(w, http.StatusOK, map[string]any{"version": "0.1.1"})
		case (strings.HasPrefix(normPath, "/v1beta/models/") || strings.HasPrefix(normPath, "/v1/models/")) && strings.Contains(normPath, ":") && r.Method == http.MethodPost:
			s.handleGeminiRoute(w, r, normPath, id, settings)
		case strings.HasPrefix(normPath, "/v1/models/") && isGetOrHead:
			s.handleGetModel(w, id, strings.TrimPrefix(normPath, "/v1/models/"))
		case normPath == "/v1/chat/completions" && r.Method == http.MethodPost:
			s.handleCompletion(w, r, id, settings, types.ProtocolOpenAI, "")
		case normPath == "/v1/responses" && r.Method == http.MethodPost:
			s.handleCompletion(w, r, id, settings, types.ProtocolResponses, "")
		case normPath == "/v1/messages" && r.Method == http.MethodPost:
			s.handleCompletion(w, r, id, settings, types.ProtocolAnthropic, "")
		case normPath == "/v1/messages/count_tokens" && r.Method == http.MethodPost:
			s.handleCountTokens(w, r)
		case normPath == "/api/chat" && r.Method == http.MethodPost:
			s.handleCompletion(w, r, id, settings, types.ProtocolOllama, "")
		default:
			access.WriteError(w, http.StatusNotFound, "Unsupported gateway route: "+r.URL.Path)
		}
	})
}

type modelEntry struct {
	ID            string
	Name          string
	OwnedBy       string
	ContextWindow int
	MaxOutput     int
}

func (s *Server) collectModelEntries(id access.Identity) []modelEntry {
	cfg := s.store.ConfigSnapshot()
	byID := make(map[string]modelEntry)
	add := func(ent modelEntry) {
		if ent.ID == "" || !access.ModelAllowed(id, ent.ID) {
			return
		}
		if ent.OwnedBy == "" {
			if prov, _, ok := strings.Cut(ent.ID, "/"); ok && prov != "" {
				ent.OwnedBy = prov
			} else {
				ent.OwnedBy = "falcon"
			}
		}
		if cur, exists := byID[ent.ID]; exists {
			if cur.Name == "" {
				cur.Name = ent.Name
			}
			if cur.ContextWindow == 0 {
				cur.ContextWindow = ent.ContextWindow
			}
			if cur.MaxOutput == 0 {
				cur.MaxOutput = ent.MaxOutput
			}
			byID[ent.ID] = cur
			return
		}
		byID[ent.ID] = ent
	}
	for _, g := range cfg.Groups {
		if g.Enabled {
			add(modelEntry{ID: g.Name, OwnedBy: "falcon-group"})
		}
	}
	for alias := range cfg.Aliases {
		add(modelEntry{ID: alias, OwnedBy: "falcon-alias"})
	}
	for _, p := range cfg.Providers {
		if !p.Enabled {
			continue
		}
		for _, m := range p.ActiveModels() {
			add(modelEntry{ID: p.ID + "/" + m, OwnedBy: p.ID})
		}
	}
	if s.plugins != nil {
		for _, pm := range s.plugins.AllModels() {
			ctxWin := pm.Context
			if ctxWin == 0 && pm.Limit != nil {
				ctxWin = pm.Limit.Context
			}
			maxOut := pm.Output
			if maxOut == 0 && pm.Limit != nil {
				maxOut = pm.Limit.Output
			}
			add(modelEntry{
				ID:            pm.ID,
				Name:          pm.Name,
				ContextWindow: ctxWin,
				MaxOutput:     maxOut,
			})
		}
	}
	out := make([]modelEntry, 0, len(byID))
	for _, ent := range byID {
		out = append(out, ent)
	}
	sort.Slice(out, func(i, j int) bool {
		return out[i].ID < out[j].ID
	})
	return out
}

func modelToOpenAIMap(ent modelEntry, created int64) map[string]any {
	ownedBy := ent.OwnedBy
	if ownedBy == "" {
		ownedBy = "falcon"
		if prov, _, ok := strings.Cut(ent.ID, "/"); ok && prov != "" {
			ownedBy = prov
		}
	}
	obj := map[string]any{
		"id":       ent.ID,
		"object":   "model",
		"created":  created,
		"owned_by": ownedBy,
	}
	if ent.Name != "" {
		obj["name"] = ent.Name
	}
	if ent.ContextWindow > 0 {
		obj["context_window"] = ent.ContextWindow
		obj["context_length"] = ent.ContextWindow
	}
	if ent.MaxOutput > 0 {
		obj["max_output_tokens"] = ent.MaxOutput
		obj["max_tokens"] = ent.MaxOutput
	}
	return obj
}

func (s *Server) handleListModels(w http.ResponseWriter, id access.Identity) {
	entries := s.collectModelEntries(id)
	data := make([]map[string]any, 0, len(entries))
	now := time.Now().Unix()
	for _, ent := range entries {
		data = append(data, modelToOpenAIMap(ent, now))
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"object": "list",
		"data":   data,
	})
}

func (s *Server) handleGetModel(w http.ResponseWriter, id access.Identity, modelID string) {
	target := strings.TrimSpace(modelID)
	if target == "" {
		access.WriteError(w, http.StatusNotFound, "Model not found")
		return
	}
	entries := s.collectModelEntries(id)
	now := time.Now().Unix()
	for _, ent := range entries {
		if ent.ID == target {
			writeJSON(w, http.StatusOK, modelToOpenAIMap(ent, now))
			return
		}
	}
	suffix := "/" + target
	for _, ent := range entries {
		if strings.HasSuffix(ent.ID, suffix) {
			writeJSON(w, http.StatusOK, modelToOpenAIMap(ent, now))
			return
		}
	}
	access.WriteError(w, http.StatusNotFound, "Model not found: "+target)
}

func (s *Server) handleGeminiListModels(w http.ResponseWriter, id access.Identity) {
	entries := s.collectModelEntries(id)
	out := make([]map[string]any, 0, len(entries))
	for _, ent := range entries {
		displayName := ent.Name
		if displayName == "" {
			displayName = ent.ID
		}
		item := map[string]any{
			"name":        "models/" + ent.ID,
			"baseModelId": ent.ID,
			"displayName": displayName,
			"supportedGenerationMethods": []string{
				"generateContent",
				"streamGenerateContent",
				"countTokens",
			},
		}
		if ent.ContextWindow > 0 {
			item["inputTokenLimit"] = ent.ContextWindow
		}
		if ent.MaxOutput > 0 {
			item["outputTokenLimit"] = ent.MaxOutput
		}
		out = append(out, item)
	}
	writeJSON(w, http.StatusOK, map[string]any{"models": out})
}

func (s *Server) handleOllamaTags(w http.ResponseWriter, id access.Identity) {
	entries := s.collectModelEntries(id)
	out := make([]map[string]any, 0, len(entries))
	for _, ent := range entries {
		out = append(out, map[string]any{
			"name":  ent.ID,
			"model": ent.ID,
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"models": out})
}

func estimateTokensFromBody(w http.ResponseWriter, r *http.Request) (int, bool) {
	raw, err := io.ReadAll(io.LimitReader(r.Body, 8<<20))
	if err != nil {
		access.WriteError(w, http.StatusBadRequest, "Failed to read request body")
		return 0, false
	}
	// Approximate tokens (~4 chars/token) cleanly.
	return max(1, len(raw)/4), true
}

func (s *Server) handleCountTokens(w http.ResponseWriter, r *http.Request) {
	if tokens, ok := estimateTokensFromBody(w, r); ok {
		writeJSON(w, http.StatusOK, map[string]any{"input_tokens": tokens})
	}
}

func (s *Server) handleGeminiRoute(w http.ResponseWriter, r *http.Request, normPath string, id access.Identity, settings types.Settings) {
	rest := normPath
	switch {
	case strings.HasPrefix(rest, "/v1beta/models/"):
		rest = strings.TrimPrefix(rest, "/v1beta/models/")
	case strings.HasPrefix(rest, "/v1/models/"):
		rest = strings.TrimPrefix(rest, "/v1/models/")
	}
	modelPart, action, hasAction := strings.Cut(rest, ":")
	if !hasAction || modelPart == "" {
		access.WriteError(w, http.StatusBadRequest, "Invalid Gemini model path")
		return
	}
	if action == "countTokens" {
		if tokens, ok := estimateTokensFromBody(w, r); ok {
			writeJSON(w, http.StatusOK, map[string]any{"totalTokens": tokens})
		}
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
		s.recordLog(id, clientProto, r.URL.Path, modelHint, "", "", http.StatusNotFound, 0, time.Since(startTime).Milliseconds(), translate.Usage{}, nil, "No enabled provider or route for model: "+modelHint)
		access.WriteError(w, http.StatusNotFound, "No enabled provider or route for model: "+modelHint)
		return
	}

	var canonReq *translate.CanonicalRequest
	var attempts []types.AttemptLog
	var lastStatus int
	var lastErr string

	for _, target := range targets {
		if target.IsPlugin {
			if err := s.tryPluginTarget(w, r, id, settings, clientProto, modelHint, target, rawBody, streamRequested, startTime, &canonReq, &attempts, &lastStatus, &lastErr); err == nil {
				return
			}
			continue
		}

		prov, ok := s.store.GetProvider(target.ProviderID)
		if !ok || !prov.Enabled {
			continue
		}
		if err := s.tryProviderTarget(w, r, id, settings, clientProto, modelHint, target, prov, rawBody, streamRequested, startTime, &canonReq, &attempts, &lastStatus, &lastErr); err == nil {
			return
		}
	}

	if lastStatus == 0 {
		lastStatus = http.StatusBadGateway
	}
	if lastErr == "" {
		lastErr = "All upstream targets failed"
	}
	s.recordLog(id, clientProto, r.URL.Path, modelHint, "", "", lastStatus, 0, time.Since(startTime).Milliseconds(), translate.Usage{}, attempts, lastErr)
	access.WriteError(w, lastStatus, lastErr)
}

func (s *Server) buildUpstreamBody(clientProto, targetProto types.Protocol, targetModel string, streamRequested bool, body []byte, canonCache **translate.CanonicalRequest) ([]byte, error) {
	if clientProto == targetProto {
		return translate.RewriteModelJSON(body, targetModel), nil
	}
	if *canonCache == nil {
		c, err := translate.DecodeRequest(clientProto, targetModel, body)
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
	rawBody []byte,
	streamRequested bool,
	startTime time.Time,
	canonCache **translate.CanonicalRequest,
	attempts *[]types.AttemptLog,
	lastStatus *int,
	lastErr *string,
) error {
	upBody, err := s.buildUpstreamBody(clientProto, prov.Protocol, target.ModelID, streamRequested, rawBody, canonCache)
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
			s.recordLog(id, clientProto, r.URL.Path, requestedModel, target.ProviderID, target.ModelID, resp.StatusCode, lat, time.Since(startTime).Milliseconds(), translate.Usage{}, *attempts, string(errBytes))
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(resp.StatusCode)
			_, _ = w.Write(errBytes)
			return nil
		}

		*attempts = append(*attempts, types.AttemptLog{Target: target.Raw, StatusCode: resp.StatusCode, LatencyMs: lat})
		s.relaySuccessResponse(w, r, id, settings, clientProto, prov.Protocol, requestedModel, target, resp, streamRequested, startTime, *attempts)
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
	rawBody []byte,
	streamRequested bool,
	startTime time.Time,
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

	// Stream-only WorkBuddy /v2 chat completions endpoints always require stream: true upstream;
	// relaySuccessResponse folds the SSE stream back into JSON when streamRequested is false.
	streamOnlyTarget := minfo.URL != "" && strings.HasSuffix(strings.TrimRight(minfo.URL, "/"), "/v2") && targetProto == types.ProtocolOpenAI
	upStream := streamRequested || streamOnlyTarget

	upBody, err := s.buildUpstreamBody(clientProto, targetProto, apiModel, upStream, rawBody, canonCache)
	if err != nil {
		*lastStatus = http.StatusBadRequest
		*lastErr = err.Error()
		return err
	}
	if upStream && !streamRequested {
		upBody = translate.ForceStreamJSON(upBody, true)
	}

	reqStart := time.Now()
	hdrs := map[string]string{"content-type": "application/json"}
	if upStream {
		hdrs["accept"] = "text/event-stream"
	}
	resp, actualProto, err := s.plugins.ExecuteRequest(r.Context(), target.ProviderID, target.ModelID, upStream, upBody, hdrs)
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
		s.recordLog(id, clientProto, r.URL.Path, requestedModel, target.ProviderID, target.ModelID, resp.StatusCode, lat, time.Since(startTime).Milliseconds(), translate.Usage{}, *attempts, string(errBytes))
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(resp.StatusCode)
		_, _ = w.Write(errBytes)
		return nil
	}

	*attempts = append(*attempts, types.AttemptLog{Target: target.Raw, StatusCode: resp.StatusCode, LatencyMs: lat})
	s.relaySuccessResponse(w, r, id, settings, clientProto, actualProto, requestedModel, target, resp, streamRequested, startTime, *attempts)
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
	attempts []types.AttemptLog,
) {
	defer resp.Body.Close()

	ct := strings.ToLower(resp.Header.Get("Content-Type"))
	upstreamStream := strings.Contains(ct, "text/event-stream") || strings.Contains(ct, "ndjson")

	if !streamRequested {
		rawResp, err := io.ReadAll(io.LimitReader(resp.Body, 16<<20))
		lat := time.Since(startTime).Milliseconds()
		if err != nil {
			access.WriteError(w, http.StatusBadGateway, err.Error())
			return
		}
		var outBytes []byte
		var usage translate.Usage
		if upstreamStream || bytes.HasPrefix(bytes.TrimSpace(rawResp), []byte("data:")) || bytes.HasPrefix(bytes.TrimSpace(rawResp), []byte("event:")) {
			canon, cerr := translate.CollectStreamToCanonical(targetProto, rawResp, requestedModel)
			if cerr == nil {
				canon.Model = requestedModel
				usage = canon.Usage
				if enc, eerr := translate.EncodeResponse(clientProto, canon); eerr == nil {
					outBytes = enc
				}
			}
		}
		if len(outBytes) == 0 {
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
		}
		s.router.RecordTTFT(target.Raw, lat)
		s.recordLog(id, clientProto, r.URL.Path, requestedModel, target.ProviderID, target.ModelID, resp.StatusCode, lat, lat, usage, attempts, "")
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

	bufPtr := streamBufPool.Get().(*[]byte)
	buf := *bufPtr
	defer streamBufPool.Put(bufPtr)

	var ttftMs int64
	lastFlush := time.Now()
	for {
		n, readErr := resp.Body.Read(buf)
		if n > 0 {
			chunk := buf[:n]
			if translator != nil {
				chunk = translator.ProcessChunk(chunk)
			} else if sniffer != nil {
				sniffer.Feed(chunk)
			}
			if len(chunk) > 0 {
				if ttftMs == 0 {
					ttftMs = max(1, time.Since(startTime).Milliseconds())
					s.router.RecordTTFT(target.Raw, ttftMs)
				}
				_, _ = w.Write(chunk)
				if flusher != nil && (bytes.IndexByte(chunk, '\n') >= 0 || time.Since(lastFlush) >= 15*time.Millisecond || readErr != nil) {
					flusher.Flush()
					lastFlush = time.Now()
				}
			}
		}
		if readErr != nil {
			break
		}
	}

	if translator != nil {
		if tail := translator.Flush(); len(tail) > 0 {
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
	s.recordLog(id, clientProto, r.URL.Path, requestedModel, target.ProviderID, target.ModelID, resp.StatusCode, ttftMs, totalLat, usage, attempts, "")
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
	attempts []types.AttemptLog,
	errMsg string,
) {
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
		RedactedCount:    0,
		Attempts:         attempts,
		Error:            errMsg,
	}, nil)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
