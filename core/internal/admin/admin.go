package admin

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/netip"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/falcon-gateway/falcon/core/internal/gateway"
	"github.com/falcon-gateway/falcon/core/internal/plugin"
	"github.com/falcon-gateway/falcon/core/internal/provider"
	"github.com/falcon-gateway/falcon/core/internal/redact"
	"github.com/falcon-gateway/falcon/core/internal/store"
	"github.com/falcon-gateway/falcon/core/internal/types"
)

// Server exposes the loopback-only Admin API (/admin/v1/*).
type Server struct {
	mu         sync.Mutex
	store      *store.Store
	gateway    *gateway.Server
	plugins    *plugin.Manager
	httpClient *http.Client
	token      string
	addr       string

	ln      net.Listener
	httpSrv *http.Server
}

// New creates an Admin Server.
func New(st *store.Store, gw *gateway.Server, pm *plugin.Manager, addr, token string, client *http.Client) *Server {
	if strings.TrimSpace(addr) == "" {
		addr = "127.0.0.1:18788"
	}
	if client == nil {
		client = &http.Client{Timeout: 20 * time.Second}
	}
	return &Server{
		store:      st,
		gateway:    gw,
		plugins:    pm,
		addr:       addr,
		token:      token,
		httpClient: client,
	}
}

// Start binds strictly on a loopback address and begins serving Admin API requests.
func (s *Server) Start() error {
	host, _, err := net.SplitHostPort(s.addr)
	if err != nil {
		return fmt.Errorf("invalid admin addr %q: %w", s.addr, err)
	}
	if host != "localhost" {
		ip, perr := netip.ParseAddr(strings.Trim(host, "[]"))
		if perr != nil || !ip.IsLoopback() {
			return fmt.Errorf("admin server must bind strictly to loopback, got %q", s.addr)
		}
	}

	ln, err := net.Listen("tcp", s.addr)
	if err != nil {
		return fmt.Errorf("admin listen %s: %w", s.addr, err)
	}
	srv := &http.Server{
		Handler:           s.handler(),
		ReadHeaderTimeout: 15 * time.Second,
	}
	s.mu.Lock()
	s.ln = ln
	s.httpSrv = srv
	s.addr = ln.Addr().String()
	s.mu.Unlock()

	go func() {
		_ = srv.Serve(ln)
	}()
	return nil
}

// Addr returns the bound admin address.
func (s *Server) Addr() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.addr
}

// Stop gracefully shuts down the admin server.
func (s *Server) Stop(ctx context.Context) error {
	s.mu.Lock()
	srv := s.httpSrv
	s.httpSrv = nil
	s.ln = nil
	s.mu.Unlock()
	if srv != nil {
		return srv.Shutdown(ctx)
	}
	return nil
}

func (s *Server) authorized(r *http.Request) bool {
	if s.token == "" {
		return true
	}
	auth := strings.TrimSpace(r.Header.Get("Authorization"))
	if len(auth) <= 7 || !strings.EqualFold(auth[:7], "Bearer ") {
		return false
	}
	got := strings.TrimSpace(auth[7:])
	return subtle.ConstantTimeCompare([]byte(got), []byte(s.token)) == 1
}

func (s *Server) handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !s.authorized(r) {
			writeErr(w, http.StatusUnauthorized, "Unauthorized admin request")
			return
		}
		path := r.URL.Path
		switch {
		case path == "/admin/v1/state" && r.Method == http.MethodGet:
			s.handleState(w)
		case path == "/admin/v1/settings" && r.Method == http.MethodPost:
			s.handleSettings(w, r)
		case path == "/admin/v1/presets" && r.Method == http.MethodGet:
			writeJSON(w, http.StatusOK, map[string]any{"presets": provider.Presets()})

		// Access Keys
		case path == "/admin/v1/keys" && r.Method == http.MethodPost:
			s.handleUpsertKey(w, r)
		case strings.HasPrefix(path, "/admin/v1/keys/") && strings.HasSuffix(path, "/rotate") && r.Method == http.MethodPost:
			id := strings.TrimSuffix(strings.TrimPrefix(path, "/admin/v1/keys/"), "/rotate")
			s.handleRotateKey(w, id)
		case strings.HasPrefix(path, "/admin/v1/keys/") && r.Method == http.MethodDelete:
			id := strings.TrimPrefix(path, "/admin/v1/keys/")
			s.handleDeleteKey(w, id)

		// Providers
		case path == "/admin/v1/providers" && r.Method == http.MethodPost:
			s.handleUpsertProvider(w, r)
		case strings.HasPrefix(path, "/admin/v1/providers/") && strings.HasSuffix(path, "/fetch-models") && r.Method == http.MethodPost:
			id := strings.TrimSuffix(strings.TrimPrefix(path, "/admin/v1/providers/"), "/fetch-models")
			s.handleFetchModels(w, r, id)
		case strings.HasPrefix(path, "/admin/v1/providers/") && strings.HasSuffix(path, "/test") && r.Method == http.MethodPost:
			id := strings.TrimSuffix(strings.TrimPrefix(path, "/admin/v1/providers/"), "/test")
			s.handleTestProvider(w, r, id)
		case strings.HasPrefix(path, "/admin/v1/providers/") && r.Method == http.MethodDelete:
			id := strings.TrimPrefix(path, "/admin/v1/providers/")
			s.handleDeleteProvider(w, id)

		// Plugins
		case path == "/admin/v1/plugins/market" && r.Method == http.MethodGet:
			items := s.plugins.Market(r.Context())
			writeJSON(w, http.StatusOK, map[string]any{"plugins": items})
		case path == "/admin/v1/plugins/install" && r.Method == http.MethodPost:
			s.handlePluginInstall(w, r)
		case path == "/admin/v1/plugins/remove" && r.Method == http.MethodPost:
			s.handlePluginRemove(w, r)
		case path == "/admin/v1/plugins/toggle" && r.Method == http.MethodPost:
			s.handlePluginToggle(w, r)
		case path == "/admin/v1/plugins/options" && r.Method == http.MethodPost:
			s.handlePluginOptions(w, r)
		case path == "/admin/v1/plugins/signin/start" && r.Method == http.MethodPost:
			s.handlePluginSignInStart(w, r)
		case strings.HasPrefix(path, "/admin/v1/plugins/signin/") && strings.HasSuffix(path, "/callback") && r.Method == http.MethodPost:
			sid := strings.TrimSuffix(strings.TrimPrefix(path, "/admin/v1/plugins/signin/"), "/callback")
			s.handlePluginSignInCallback(w, r, sid)
		case strings.HasPrefix(path, "/admin/v1/plugins/signin/") && r.Method == http.MethodGet:
			sid := strings.TrimPrefix(path, "/admin/v1/plugins/signin/")
			s.handlePluginSignInGet(w, r, sid)
		case strings.HasPrefix(path, "/admin/v1/plugins/accounts/") && strings.HasSuffix(path, "/checkin") && r.Method == http.MethodPost:
			rest := strings.TrimSuffix(strings.TrimPrefix(path, "/admin/v1/plugins/accounts/"), "/checkin")
			provID, accID, ok := strings.Cut(rest, "/")
			if !ok {
				writeErr(w, http.StatusBadRequest, "invalid account path")
				return
			}
			s.handlePluginCheckin(w, r, provID, accID)
		case strings.HasPrefix(path, "/admin/v1/plugins/accounts/") && r.Method == http.MethodDelete:
			rest := strings.TrimPrefix(path, "/admin/v1/plugins/accounts/")
			provID, accID, ok := strings.Cut(rest, "/")
			if !ok {
				writeErr(w, http.StatusBadRequest, "invalid account path")
				return
			}
			s.handlePluginRemoveAccount(w, r, provID, accID)
		case path == "/admin/v1/plugins/quotas/refresh" && r.Method == http.MethodPost:
			if err := s.plugins.RefreshQuotas(r.Context()); err != nil {
				writeErr(w, http.StatusInternalServerError, err.Error())
				return
			}
			writeJSON(w, http.StatusOK, map[string]any{"ok": true, "plugins": s.plugins.StatePlugins()})

		// Routing & Redaction
		case path == "/admin/v1/groups" && r.Method == http.MethodPost:
			s.handleUpsertGroup(w, r)
		case strings.HasPrefix(path, "/admin/v1/groups/") && r.Method == http.MethodDelete:
			id := strings.TrimPrefix(path, "/admin/v1/groups/")
			if err := s.store.DeleteGroup(id); err != nil {
				writeErr(w, http.StatusNotFound, err.Error())
				return
			}
			writeJSON(w, http.StatusOK, map[string]any{"ok": true})
		case path == "/admin/v1/aliases" && r.Method == http.MethodPost:
			s.handleAliases(w, r)
		case path == "/admin/v1/redact/preview" && r.Method == http.MethodPost:
			s.handleRedactPreview(w, r)

		// Usage, Logs, Backup
		case path == "/admin/v1/usage" && r.Method == http.MethodGet:
			rng := r.URL.Query().Get("range")
			writeJSON(w, http.StatusOK, s.store.GetUsageSummary(rng))
		case path == "/admin/v1/logs" && r.Method == http.MethodGet:
			limit := 100
			if raw := r.URL.Query().Get("limit"); raw != "" {
				if n, err := strconv.Atoi(raw); err == nil && n > 0 {
					limit = n
				}
			}
			writeJSON(w, http.StatusOK, map[string]any{"logs": s.store.GetLogs(limit)})
		case path == "/admin/v1/logs/clear" && r.Method == http.MethodPost:
			if err := s.store.ClearLogs(); err != nil {
				writeErr(w, http.StatusInternalServerError, err.Error())
				return
			}
			writeJSON(w, http.StatusOK, map[string]any{"ok": true})
		case path == "/admin/v1/backup/export" && r.Method == http.MethodGet:
			inc := r.URL.Query().Get("includeSecrets") == "true"
			writeJSON(w, http.StatusOK, s.store.ExportBackup(inc))
		case path == "/admin/v1/backup/import" && r.Method == http.MethodPost:
			s.handleBackupImport(w, r)

		default:
			writeErr(w, http.StatusNotFound, "Unknown admin endpoint: "+path)
		}
	})
}

func (s *Server) handleState(w http.ResponseWriter) {
	cfg := s.store.ConfigSnapshot()
	var pluginsState []plugin.InstalledPluginState
	if s.plugins != nil {
		pluginsState = s.plugins.StatePlugins()
	} else {
		pluginsState = []plugin.InstalledPluginState{}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"status":        s.gateway.Status(),
		"settings":      cfg.Settings,
		"keys":          s.store.ListKeysMasked(),
		"providers":     s.store.ListProvidersMasked(),
		"plugins":       pluginsState,
		"groups":        cfg.Groups,
		"aliases":       cfg.Aliases,
		"redactSummary": s.store.RedactSummary(),
		"usageSummary":  s.store.GetUsageSummary("today"),
	})
}

func (s *Server) handleSettings(w http.ResponseWriter, r *http.Request) {
	var patch types.SettingsPatch
	if err := decodeBody(r, &patch); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	prev := s.store.Settings()
	settings, relisten, err := s.store.UpdateSettings(patch)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if relisten {
		if err := s.gateway.Relisten(); err != nil {
			_, _, _ = s.store.UpdateSettings(types.SettingsPatch{
				Port:       &prev.Port,
				LanEnabled: &prev.LanEnabled,
			})
			writeErr(w, http.StatusInternalServerError, "gateway relisten failed (reverted port/lanEnabled): "+err.Error())
			return
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"settings": settings,
		"status":   s.gateway.Status(),
	})
}

func (s *Server) handleUpsertKey(w http.ResponseWriter, r *http.Request) {
	var in types.AccessKey
	if err := decodeBody(r, &in); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	k, created, err := s.store.CreateOrUpdateKey(in)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"key": k, "created": created})
}

func (s *Server) handleRotateKey(w http.ResponseWriter, id string) {
	k, err := s.store.RotateKey(id)
	if err != nil {
		writeErr(w, http.StatusNotFound, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"key": k})
}

func (s *Server) handleDeleteKey(w http.ResponseWriter, id string) {
	if err := s.store.DeleteKey(id); err != nil {
		writeErr(w, http.StatusNotFound, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) handleUpsertProvider(w http.ResponseWriter, r *http.Request) {
	var in types.Provider
	if err := decodeBody(r, &in); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	p, err := s.store.UpsertProvider(in)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"provider": p})
}

func (s *Server) handleDeleteProvider(w http.ResponseWriter, id string) {
	if err := s.store.DeleteProvider(id); err != nil {
		writeErr(w, http.StatusNotFound, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) handleFetchModels(w http.ResponseWriter, r *http.Request, id string) {
	p, ok := s.store.GetProvider(id)
	if !ok {
		writeErr(w, http.StatusNotFound, "provider not found")
		return
	}
	models, err := provider.FetchModels(r.Context(), s.httpClient, p)
	if err != nil {
		writeErr(w, http.StatusBadGateway, err.Error())
		return
	}
	_ = s.store.UpdateProviderAvailableModels(id, models)
	masked := s.store.ListProvidersMasked()
	var updated *types.Provider
	for i := range masked {
		if masked[i].ID == id {
			updated = &masked[i]
			break
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"models":   models,
		"provider": updated,
	})
}

func (s *Server) handleTestProvider(w http.ResponseWriter, r *http.Request, id string) {
	p, ok := s.store.GetProvider(id)
	if !ok {
		writeErr(w, http.StatusNotFound, "provider not found")
		return
	}
	var reqBody struct {
		Model string `json:"model"`
	}
	_ = decodeBody(r, &reqBody)
	res := provider.TestConnectivity(r.Context(), s.httpClient, p, reqBody.Model)
	s.store.UpdateProviderTest(id, res)
	writeJSON(w, http.StatusOK, res)
}

func (s *Server) handlePluginInstall(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Package string `json:"package"`
		Spec    string `json:"spec"`
	}
	if err := decodeBody(r, &body); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	spec := strings.TrimSpace(body.Spec)
	if spec == "" {
		spec = strings.TrimSpace(body.Package)
	}
	st, err := s.plugins.Install(r.Context(), spec)
	if err != nil {
		writeErr(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"plugin":  st,
		"plugins": s.plugins.StatePlugins(),
	})
}

func (s *Server) handlePluginRemove(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Package string `json:"package"`
		Spec    string `json:"spec"`
	}
	if err := decodeBody(r, &body); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	pkg := body.Package
	if pkg == "" {
		pkg = body.Spec
	}
	if err := s.plugins.Remove(r.Context(), pkg); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "plugins": s.plugins.StatePlugins()})
}

func (s *Server) handlePluginToggle(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Package string `json:"package"`
		Enabled bool   `json:"enabled"`
	}
	if err := decodeBody(r, &body); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if err := s.plugins.Toggle(r.Context(), body.Package, body.Enabled); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "plugins": s.plugins.StatePlugins()})
}

func (s *Server) handlePluginOptions(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Package    string         `json:"package"`
		Options    map[string]any `json:"options"`
		ProviderID string         `json:"providerId"`
		Key        string         `json:"key"`
		Value      bool           `json:"value"`
	}
	if err := decodeBody(r, &body); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if body.Package != "" && body.Options != nil {
		if err := s.plugins.SetPackageOptions(r.Context(), body.Package, body.Options); err != nil {
			writeErr(w, http.StatusBadRequest, err.Error())
			return
		}
	} else {
		if err := s.plugins.SetOption(r.Context(), body.ProviderID, body.Key, body.Value); err != nil {
			writeErr(w, http.StatusBadRequest, err.Error())
			return
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "plugins": s.plugins.StatePlugins()})
}

func (s *Server) handlePluginSignInStart(w http.ResponseWriter, r *http.Request) {
	var req plugin.SignInStartRequest
	if err := decodeBody(r, &req); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	res, err := s.plugins.StartSignIn(r.Context(), req)
	if err != nil {
		writeErr(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, res)
}

func (s *Server) handlePluginSignInGet(w http.ResponseWriter, r *http.Request, sid string) {
	res, err := s.plugins.GetSignInSession(r.Context(), sid)
	if err != nil {
		writeErr(w, http.StatusNotFound, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, res)
}

func (s *Server) handlePluginSignInCallback(w http.ResponseWriter, r *http.Request, sid string) {
	var body struct {
		Code  string `json:"code"`
		Input string `json:"input"`
		Value string `json:"value"`
	}
	if err := decodeBody(r, &body); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	code := body.Code
	if code == "" {
		code = body.Input
	}
	if code == "" {
		code = body.Value
	}
	res, err := s.plugins.CompleteSignInCallback(r.Context(), sid, code)
	if err != nil {
		writeErr(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, res)
}

func (s *Server) handlePluginRemoveAccount(w http.ResponseWriter, r *http.Request, provID, accID string) {
	if err := s.plugins.RemoveAccount(r.Context(), provID, accID); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "plugins": s.plugins.StatePlugins()})
}

func (s *Server) handlePluginCheckin(w http.ResponseWriter, r *http.Request, provID, accID string) {
	res, err := s.plugins.CheckinAccount(r.Context(), provID, accID)
	if err != nil {
		writeErr(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, res)
}

func (s *Server) handleUpsertGroup(w http.ResponseWriter, r *http.Request) {
	var g types.RoutingGroup
	if err := decodeBody(r, &g); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	saved, err := s.store.UpsertGroup(g)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"group": saved})
}

func (s *Server) handleAliases(w http.ResponseWriter, r *http.Request) {
	raw, err := io.ReadAll(io.LimitReader(r.Body, 2<<20))
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	var payload struct {
		Aliases json.RawMessage `json:"aliases"`
		Alias   string          `json:"alias"`
		Target  string          `json:"target"`
		Delete  string          `json:"delete"`
	}
	if err := json.Unmarshal(raw, &payload); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if len(payload.Aliases) > 0 && string(payload.Aliases) != "null" {
		m := map[string]string{}
		if err := json.Unmarshal(payload.Aliases, &m); err != nil {
			var list []struct {
				Alias  string `json:"alias"`
				Target string `json:"target"`
			}
			if err2 := json.Unmarshal(payload.Aliases, &list); err2 != nil {
				writeErr(w, http.StatusBadRequest, err.Error())
				return
			}
			for _, item := range list {
				if item.Alias != "" && item.Target != "" {
					m[item.Alias] = item.Target
				}
			}
		}
		out, err := s.store.SetAliases(m)
		if err != nil {
			writeErr(w, http.StatusBadRequest, err.Error())
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"aliases": out})
		return
	}
	if payload.Delete != "" {
		out, err := s.store.UpsertAlias(payload.Delete, "")
		if err != nil {
			writeErr(w, http.StatusBadRequest, err.Error())
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"aliases": out})
		return
	}
	out, err := s.store.UpsertAlias(payload.Alias, payload.Target)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"aliases": out})
}

func (s *Server) handleRedactPreview(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Text string `json:"text"`
	}
	if err := decodeBody(r, &body); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	res := redact.Preview(s.store.Settings(), body.Text)
	writeJSON(w, http.StatusOK, res)
}

func (s *Server) handleBackupImport(w http.ResponseWriter, r *http.Request) {
	var bundle types.BackupBundle
	if err := decodeBody(r, &bundle); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if err := s.store.ImportBackup(bundle); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	_ = s.gateway.Relisten()
	if s.plugins != nil {
		_ = s.plugins.Reload(r.Context())
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "status": s.gateway.Status()})
}

func decodeBody(r *http.Request, dst any) error {
	raw, err := io.ReadAll(io.LimitReader(r.Body, 8<<20))
	if err != nil {
		return err
	}
	if len(strings.TrimSpace(string(raw))) == 0 {
		return errors.New("empty request body")
	}
	return json.Unmarshal(raw, dst)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]any{"error": msg})
}
