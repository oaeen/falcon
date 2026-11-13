package plugin

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/falcon-gateway/falcon/core/internal/store"
	"github.com/falcon-gateway/falcon/core/internal/translate"
	"github.com/falcon-gateway/falcon/core/internal/types"
)

var deviceCodeRe = regexp.MustCompile(`(?i)(?:code|码)\s*[:：]\s*([A-Za-z0-9]{3,8}(?:-[A-Za-z0-9]{3,8})+|[A-Z0-9]{6,12})|\b([A-Z0-9]{4}-[A-Z0-9]{4})\b`)

// Manager coordinates plugin installation, marketplace listing, Bun/Embedded host lifecycle,
// sign-in sessions, account quotas, and gateway request proxying.
type Manager struct {
	mu           sync.RWMutex
	store        *store.Store
	httpClient   *http.Client
	bunPath      string
	runtimeMode  string // "bun" | "embedded"
	bunHost      *BunHost
	embeddedHost *EmbeddedHost

	loadedErrors map[string]string                // package -> error
	providers    map[string]PluginProviderState   // providerId -> state
	pkgProviders map[string][]PluginProviderState // package -> []state
	quotas       map[string]*PluginUsage          // accountId -> usage
	checkins     map[string]*PluginCheckinResult  // accountId -> checkin
	sessions     map[string]*SignInSessionState   // sessionId -> state
	bunSessMap   map[string]string                // falconSessionId -> hostSessionId
}

// NewManager initializes the plugin manager, automatically choosing Bun or pure-Go Embedded mode.
func NewManager(st *store.Store, bunEnv, cacheDir, caBundle, dnsServers string, client *http.Client) *Manager {
	if client == nil {
		client = &http.Client{Timeout: 90 * time.Second}
	}
	bunPath := DetectBun(bunEnv)
	mode := "embedded"
	if bunPath != "" {
		mode = "bun"
	}
	m := &Manager{
		store:        st,
		httpClient:   client,
		bunPath:      bunPath,
		runtimeMode:  mode,
		embeddedHost: NewEmbeddedHost(st.DataDir(), client),
		loadedErrors: make(map[string]string),
		providers:    make(map[string]PluginProviderState),
		pkgProviders: make(map[string][]PluginProviderState),
		quotas:       make(map[string]*PluginUsage),
		checkins:     make(map[string]*PluginCheckinResult),
		sessions:     make(map[string]*SignInSessionState),
		bunSessMap:   make(map[string]string),
	}
	if mode == "bun" {
		m.bunHost = NewBunHost(bunPath, st.DataDir(), cacheDir, caBundle, dnsServers, m.onHostEvent)
	}
	return m
}

// RuntimeMode returns "bun" or "embedded".
func (m *Manager) RuntimeMode() string {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.runtimeMode
}

func (m *Manager) onHostEvent(ev map[string]any) {
	// Refresh providers asynchronously on auth change events
	if t, _ := ev["event"].(string); t == "auth" || t == "signIn" {
		go func() {
			ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
			defer cancel()
			_ = m.RefreshProviders(ctx)
		}()
	}
}

func (m *Manager) Stop() {
	if m.bunHost != nil {
		m.bunHost.Stop()
	}
}

func (m *Manager) optionsPath() string {
	return filepath.Join(m.store.DataDir(), "plugin-options.json")
}

func (m *Manager) readOptions() map[string]map[string]bool {
	raw, err := os.ReadFile(m.optionsPath())
	if err != nil {
		return map[string]map[string]bool{}
	}
	var out map[string]map[string]bool
	if json.Unmarshal(raw, &out) != nil || out == nil {
		return map[string]map[string]bool{}
	}
	return out
}

func (m *Manager) saveOptions(opts map[string]map[string]bool) error {
	return store.WriteAtomicJSON(m.optionsPath(), opts)
}

// Reload starts/restarts the active host (if plugins are enabled) and refreshes discovered providers.
func (m *Manager) Reload(ctx context.Context) error {
	cfg := m.store.ConfigSnapshot()
	var active []types.InstalledPluginEntry
	for _, p := range cfg.Plugins {
		if p.Enabled {
			active = append(active, p)
		}
	}

	if m.runtimeMode == "bun" && m.bunHost != nil {
		if len(active) == 0 {
			m.bunHost.Stop()
			m.mu.Lock()
			m.loadedErrors = map[string]string{}
			m.providers = map[string]PluginProviderState{}
			m.pkgProviders = map[string][]PluginProviderState{}
			m.mu.Unlock()
			return nil
		}
		var list []map[string]any
		for _, p := range active {
			list = append(list, map[string]any{
				"spec":   p.Package,
				"target": PackageDir(m.store.DataDir(), p.Package),
			})
		}
		loaded, err := m.bunHost.StartAndInit(ctx, list, m.readOptions())
		if err != nil {
			// Graceful fallback to embedded mode if Bun fails to launch at runtime
			m.mu.Lock()
			m.runtimeMode = "embedded"
			m.mu.Unlock()
			return m.RefreshProviders(ctx)
		}
		errs := make(map[string]string)
		for _, item := range loaded {
			spec, _ := item["spec"].(string)
			errMsg, _ := item["error"].(string)
			if spec != "" && errMsg != "" {
				errs[spec] = errMsg
			}
		}
		m.mu.Lock()
		m.loadedErrors = errs
		m.mu.Unlock()
	}

	return m.RefreshProviders(ctx)
}

// RefreshProviders refreshes provider & model metadata from the active host.
func (m *Manager) RefreshProviders(ctx context.Context) error {
	cfg := m.store.ConfigSnapshot()
	if m.runtimeMode == "bun" && m.bunHost != nil && m.bunHost.IsRunning() {
		var rows []struct {
			ID              string             `json:"id"`
			Spec            string             `json:"spec"`
			Name            string             `json:"name"`
			Protocol        types.Protocol     `json:"protocol"`
			Methods         []PluginAuthMethod `json:"methods"`
			SupportsUsage   bool               `json:"supportsUsage"`
			SupportsCheckin bool               `json:"supportsCheckin"`
			Options         []struct {
				Key           string            `json:"key"`
				Label         string            `json:"label"`
				Description   string            `json:"description"`
				Default       bool              `json:"default"`
				Labels        map[string]string `json:"labels"`
				Descriptions  map[string]string `json:"descriptions"`
				FiltersModels bool              `json:"filtersModels"`
			} `json:"options"`
			Accounts  []PluginAccountState `json:"accounts"`
			Models    []PluginModelInfo    `json:"models"`
			ListError string               `json:"listError"`
		}
		if err := m.bunHost.Call(ctx, "providers", map[string]any{}, &rows); err == nil {
			opts := m.readOptions()
			provMap := make(map[string]PluginProviderState, len(rows))
			pkgMap := make(map[string][]PluginProviderState)
			m.mu.RLock()
			quotasCopy := m.quotas
			checkinsCopy := m.checkins
			m.mu.RUnlock()

			for _, r := range rows {
				if r.Protocol == "" {
					r.Protocol = types.ProtocolOpenAI
				}
				var pOpts []PluginOption
				for _, o := range r.Options {
					val := o.Default
					if ov, ok := opts[r.ID][o.Key]; ok {
						val = ov
					}
					lblZh := o.Labels["zh"]
					if lblZh == "" {
						lblZh = o.Label
					}
					lblEn := o.Labels["en"]
					if lblEn == "" {
						lblEn = o.Label
					}
					descZh := o.Descriptions["zh"]
					if descZh == "" {
						descZh = o.Description
					}
					descEn := o.Descriptions["en"]
					if descEn == "" {
						descEn = o.Description
					}
					pOpts = append(pOpts, PluginOption{
						Key:           o.Key,
						Label:         lblZh,
						LabelEn:       lblEn,
						Description:   descZh,
						DescriptionEn: descEn,
						Value:         val,
						FiltersModels: o.FiltersModels,
					})
				}
				for i := range r.Accounts {
					if q, ok := quotasCopy[r.Accounts[i].ID]; ok {
						r.Accounts[i].Quota = q
					}
					if c, ok := checkinsCopy[r.Accounts[i].ID]; ok {
						r.Accounts[i].LastCheckin = c
					}
				}
				st := PluginProviderState{
					ID:              r.ID,
					Name:            r.Name,
					Protocol:        r.Protocol,
					Models:          r.Models,
					Methods:         r.Methods,
					Options:         pOpts,
					SupportsUsage:   r.SupportsUsage,
					SupportsCheckin: r.SupportsCheckin,
					Accounts:        r.Accounts,
					ListError:       r.ListError,
				}
				provMap[r.ID] = st
				pkgMap[r.Spec] = append(pkgMap[r.Spec], st)
			}
			m.mu.Lock()
			m.providers = provMap
			m.pkgProviders = pkgMap
			m.mu.Unlock()
			return nil
		}
	}

	// Embedded pure-Go mode
	pkgMap := m.embeddedHost.ProvidersForEntries(ctx, cfg.Plugins, BuiltinMarket())
	provMap := make(map[string]PluginProviderState)
	m.mu.RLock()
	quotasCopy := m.quotas
	checkinsCopy := m.checkins
	m.mu.RUnlock()
	for pkg, list := range pkgMap {
		for idx := range list {
			for ai := range list[idx].Accounts {
				list[idx].Accounts[ai].Enabled = true
				aid := list[idx].Accounts[ai].ID
				if q, ok := quotasCopy[aid]; ok {
					list[idx].Accounts[ai].Quota = q
					list[idx].Accounts[ai].Quotas = normalizeQuotaWindows(q.Windows)
				}
				if c, ok := checkinsCopy[aid]; ok {
					list[idx].Accounts[ai].LastCheckin = c
				}
			}
			provMap[list[idx].ID] = list[idx]
		}
		pkgMap[pkg] = list
	}
	m.mu.Lock()
	m.providers = provMap
	m.pkgProviders = pkgMap
	m.mu.Unlock()
	return nil
}

// Market returns the marketplace directory annotated with local installation status.
func (m *Manager) Market(ctx context.Context) []MarketItem {
	settings := m.store.Settings()
	items := FetchLiveMarket(ctx, m.httpClient, settings.ChinaMirror)
	cfg := m.store.ConfigSnapshot()

	installed := make(map[string]types.InstalledPluginEntry, len(cfg.Plugins))
	for _, p := range cfg.Plugins {
		installed[p.Package] = p
	}
	m.mu.RLock()
	errs := m.loadedErrors
	m.mu.RUnlock()

	seen := make(map[string]bool)
	for i := range items {
		seen[items[i].Package] = true
		if ent, ok := installed[items[i].Package]; ok {
			items[i].Installed = true
			items[i].Enabled = ent.Enabled
			items[i].Version = InstalledVersion(m.store.DataDir(), ent.Package)
			items[i].Error = errs[ent.Package]
		}
	}
	for _, ent := range cfg.Plugins {
		if seen[ent.Package] {
			continue
		}
		items = append(items, MarketItem{
			Package:   ent.Package,
			Name:      shortPluginSlug(ent.Package),
			Kind:      "provider",
			Installed: true,
			Enabled:   ent.Enabled,
			Version:   InstalledVersion(m.store.DataDir(), ent.Package),
			Error:     errs[ent.Package],
		})
	}
	return items
}

// Install downloads, verifies, installs, and activates a plugin package.
func (m *Manager) Install(ctx context.Context, rawSpec string) (InstalledPluginState, error) {
	items := BuiltinMarket()
	spec := ResolveSpec(rawSpec, items)
	if spec == "" {
		return InstalledPluginState{}, errors.New("package spec is required")
	}
	settings := m.store.Settings()
	res, err := InstallPackage(ctx, m.httpClient, m.store.DataDir(), spec, settings.ChinaMirror, m.bunPath)
	if err != nil {
		return InstalledPluginState{}, err
	}
	entry := types.InstalledPluginEntry{
		Package: res.Package,
		Spec:    spec,
		Enabled: true,
	}
	if err := m.store.UpsertPluginEntry(entry); err != nil {
		return InstalledPluginState{}, err
	}
	if err := m.Reload(ctx); err != nil {
		return InstalledPluginState{}, err
	}
	for _, st := range m.StatePlugins() {
		if st.Package == res.Package {
			return st, nil
		}
	}
	return InstalledPluginState{
		Package: res.Package,
		Name:    shortPluginSlug(res.Package),
		Enabled: true,
		Version: res.Version,
	}, nil
}

// Remove uninstalls a plugin and removes its files from disk.
func (m *Manager) Remove(ctx context.Context, pkg string) error {
	pkg = PackageNameOf(pkg)
	if err := m.store.RemovePluginEntry(pkg); err != nil {
		return err
	}
	_ = os.RemoveAll(PackageDir(m.store.DataDir(), pkg))
	return m.Reload(ctx)
}

// Toggle enables or disables an installed plugin.
func (m *Manager) Toggle(ctx context.Context, pkg string, enabled bool) error {
	pkg = PackageNameOf(pkg)
	if err := m.store.TogglePluginEntry(pkg, enabled); err != nil {
		return err
	}
	return m.Reload(ctx)
}

// SetOption updates a plugin provider boolean option.
func (m *Manager) SetOption(ctx context.Context, providerID, key string, val bool) error {
	opts := m.readOptions()
	if opts[providerID] == nil {
		opts[providerID] = map[string]bool{}
	}
	opts[providerID][key] = val
	if err := m.saveOptions(opts); err != nil {
		return err
	}
	if m.runtimeMode == "bun" && m.bunHost != nil && m.bunHost.IsRunning() {
		_ = m.bunHost.Call(ctx, "setProviderOptions", map[string]any{"options": opts}, nil)
	}
	return m.RefreshProviders(ctx)
}

// SetPackageOptions updates boolean options across a plugin package's providers.
func (m *Manager) SetPackageOptions(ctx context.Context, pkg string, values map[string]any) error {
	if len(values) == 0 {
		return nil
	}
	m.mu.RLock()
	provs := m.pkgProviders[PackageNameOf(pkg)]
	m.mu.RUnlock()
	opts := m.readOptions()
	targetIDs := make([]string, 0, len(provs))
	for _, p := range provs {
		targetIDs = append(targetIDs, p.ID)
	}
	if len(targetIDs) == 0 && pkg != "" {
		for _, it := range BuiltinMarket() {
			if it.Package == PackageNameOf(pkg) {
				targetIDs = append(targetIDs, it.Providers...)
			}
		}
	}
	if len(targetIDs) == 0 {
		targetIDs = append(targetIDs, PackageNameOf(pkg))
	}
	for _, pid := range targetIDs {
		if opts[pid] == nil {
			opts[pid] = map[string]bool{}
		}
		for k, raw := range values {
			if b, ok := raw.(bool); ok {
				opts[pid][k] = b
			}
		}
	}
	if err := m.saveOptions(opts); err != nil {
		return err
	}
	if m.runtimeMode == "bun" && m.bunHost != nil && m.bunHost.IsRunning() {
		_ = m.bunHost.Call(ctx, "setProviderOptions", map[string]any{"options": opts}, nil)
	}
	return m.RefreshProviders(ctx)
}

func normalizeQuotaWindows(in []QuotaWindow) []QuotaWindow {
	if len(in) == 0 {
		return nil
	}
	out := make([]QuotaWindow, len(in))
	for i, w := range in {
		if w.Label == "" {
			w.Label = w.Name
		}
		if w.ResetAt == "" {
			w.ResetAt = w.ResetsAt
		}
		if w.RemainingPct == nil && w.Limit > 0 && w.Used != nil {
			rem := ((w.Limit - *w.Used) / w.Limit) * 100
			if rem < 0 {
				rem = 0
			}
			w.RemainingPct = &rem
		}
		out[i] = w
	}
	return out
}

// StatePlugins returns the current installed plugins list for /admin/v1/state.
func (m *Manager) StatePlugins() []InstalledPluginState {
	cfg := m.store.ConfigSnapshot()
	market := BuiltinMarket()
	names := make(map[string]string, len(market))
	for _, it := range market {
		names[it.Package] = it.Name
	}

	m.mu.RLock()
	defer m.mu.RUnlock()

	out := make([]InstalledPluginState, 0, len(cfg.Plugins))
	for _, ent := range cfg.Plugins {
		name := names[ent.Package]
		if name == "" {
			name = shortPluginSlug(ent.Package)
		}
		provs := m.pkgProviders[ent.Package]
		if provs == nil {
			provs = []PluginProviderState{}
		}
		provIDs := make([]string, 0, len(provs))
		models := make([]string, 0)
		accounts := make([]PluginAccountState, 0)
		optMap := make(map[string]any)
		for _, pp := range provs {
			provIDs = append(provIDs, pp.ID)
			for _, mod := range pp.Models {
				models = append(models, pp.ID+"/"+mod.ID)
			}
			for _, opt := range pp.Options {
				optMap[opt.Key] = opt.Value
			}
			for _, acc := range pp.Accounts {
				acc.Enabled = true
				if acc.Quota != nil && len(acc.Quotas) == 0 {
					acc.Quotas = normalizeQuotaWindows(acc.Quota.Windows)
				}
				accounts = append(accounts, acc)
			}
		}
		out = append(out, InstalledPluginState{
			Package:     ent.Package,
			ID:          ent.Package,
			Name:        name,
			Installed:   true,
			Enabled:     ent.Enabled,
			Version:     InstalledVersion(m.store.DataDir(), ent.Package),
			Error:       m.loadedErrors[ent.Package],
			ProviderIDs: provIDs,
			Models:      models,
			Options:     optMap,
			Accounts:    accounts,
			Providers:   provs,
		})
	}
	return out
}

// StartSignIn begins an API-key, keyless, or OAuth sign-in flow for a plugin provider.
func (m *Manager) StartSignIn(ctx context.Context, req SignInStartRequest) (SignInSessionState, error) {
	if req.ProviderID == "" && req.Package != "" {
		pkg := PackageNameOf(req.Package)
		m.mu.RLock()
		if provs := m.pkgProviders[pkg]; len(provs) > 0 {
			req.ProviderID = provs[0].ID
		}
		m.mu.RUnlock()
		if req.ProviderID == "" {
			for _, it := range BuiltinMarket() {
				if it.Package == pkg && len(it.Providers) > 0 {
					req.ProviderID = it.Providers[0]
					break
				}
			}
		}
	}
	if m.runtimeMode == "bun" && m.bunHost != nil && m.bunHost.IsRunning() {
		m.mu.RLock()
		prov, hasProv := m.providers[req.ProviderID]
		m.mu.RUnlock()
		methodType := "api"
		if hasProv && req.MethodIndex >= 0 && req.MethodIndex < len(prov.Methods) {
			methodType = prov.Methods[req.MethodIndex].Type
		}
		sid := store.NewID("signin")
		if methodType == "api" || req.APIKey != "" {
			var res struct {
				Ok       bool   `json:"ok"`
				Provider string `json:"provider"`
				Account  string `json:"account"`
				Error    string `json:"error"`
			}
			err := m.bunHost.Call(ctx, "apiKey", map[string]any{
				"provider": req.ProviderID,
				"method":   req.MethodIndex,
				"key":      req.APIKey,
				"inputs":   req.Inputs,
				"account":  req.Account,
			}, &res)
			if err != nil {
				st := SignInSessionState{SessionID: sid, ProviderID: req.ProviderID, Status: "failed", Error: err.Error()}
				m.enrichSignInState(&st)
				return st, err
			}
			if !res.Ok {
				st := SignInSessionState{SessionID: sid, ProviderID: req.ProviderID, Status: "failed", Error: res.Error}
				m.enrichSignInState(&st)
				return st, errors.New(res.Error)
			}
			_ = m.RefreshProviders(ctx)
			st := SignInSessionState{
				SessionID:  sid,
				ProviderID: res.Provider,
				Status:     "completed",
				Method:     "api",
				AccountID:  res.Account,
			}
			m.enrichSignInState(&st)
			m.mu.Lock()
			m.sessions[sid] = &st
			m.mu.Unlock()
			return st, nil
		}

		// OAuth via Bun host
		var authRes struct {
			Ok           bool   `json:"ok"`
			Session      string `json:"session"`
			URL          string `json:"url"`
			Instructions string `json:"instructions"`
			Method       string `json:"method"`
			Error        string `json:"error"`
		}
		err := m.bunHost.Call(ctx, "authorize", map[string]any{
			"provider": req.ProviderID,
			"method":   req.MethodIndex,
			"inputs":   req.Inputs,
			"account":  req.Account,
		}, &authRes)
		if err != nil {
			return SignInSessionState{}, err
		}
		if !authRes.Ok {
			return SignInSessionState{}, errors.New(authRes.Error)
		}
		st := SignInSessionState{
			SessionID:    sid,
			ProviderID:   req.ProviderID,
			Status:       "pending",
			Method:       authRes.Method,
			URL:          authRes.URL,
			Instructions: authRes.Instructions,
			DeviceCode:   extractDeviceCode(authRes.Instructions),
		}
		m.enrichSignInState(&st)
		m.mu.Lock()
		m.sessions[sid] = &st
		m.bunSessMap[sid] = authRes.Session
		m.mu.Unlock()

		// For auto device-code polling, run callback asynchronously
		if authRes.Method == "auto" {
			go func() {
				bgCtx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
				defer cancel()
				_, _ = m.CompleteSignInCallback(bgCtx, sid, "")
			}()
		}
		return st, nil
	}

	st, err := m.embeddedHost.StartSignIn(ctx, req)
	if err != nil {
		m.enrichSignInState(&st)
		return st, err
	}
	if st.Status == "completed" {
		_ = m.RefreshProviders(ctx)
	}
	m.enrichSignInState(&st)
	m.mu.Lock()
	cp := st
	m.sessions[st.SessionID] = &cp
	m.mu.Unlock()
	return st, nil
}

// GetSignInSession returns the current status of a sign-in session (polling device flow if needed).
func (m *Manager) GetSignInSession(ctx context.Context, sid string) (SignInSessionState, error) {
	m.mu.RLock()
	st, ok := m.sessions[sid]
	_, isBun := m.bunSessMap[sid]
	m.mu.RUnlock()
	if !ok {
		return SignInSessionState{}, errors.New("sign-in session not found")
	}
	if !isBun && st.Status == "pending" && st.Method == "auto" {
		return m.CompleteSignInCallback(ctx, sid, "")
	}
	cp := *st
	m.enrichSignInState(&cp)
	return cp, nil
}

// CompleteSignInCallback finishes an OAuth paste-code or device-code sign-in session.
func (m *Manager) CompleteSignInCallback(ctx context.Context, sid, code string) (SignInSessionState, error) {
	m.mu.RLock()
	st, ok := m.sessions[sid]
	hostSid, isBun := m.bunSessMap[sid]
	m.mu.RUnlock()
	if !ok {
		return SignInSessionState{}, errors.New("sign-in session not found")
	}
	if isBun && m.bunHost != nil {
		var cbRes struct {
			Ok       bool   `json:"ok"`
			Provider string `json:"provider"`
			Account  string `json:"account"`
			Error    string `json:"error"`
		}
		err := m.bunHost.Call(ctx, "callback", map[string]any{
			"session": hostSid,
			"code":    code,
		}, &cbRes)
		m.mu.Lock()
		delete(m.bunSessMap, sid)
		if err != nil {
			st.Status = "failed"
			st.Error = err.Error()
		} else if !cbRes.Ok {
			st.Status = "failed"
			st.Error = cbRes.Error
		} else {
			st.Status = "completed"
			st.AccountID = cbRes.Account
		}
		res := *st
		m.mu.Unlock()
		if res.Status == "completed" {
			_ = m.RefreshProviders(ctx)
		}
		m.enrichSignInState(&res)
		return res, err
	}

	res, err := m.embeddedHost.CompleteCallback(ctx, sid, code)
	if err != nil {
		return SignInSessionState{}, err
	}
	if res.Status == "completed" {
		_ = m.RefreshProviders(ctx)
	}
	m.enrichSignInState(&res)
	m.mu.Lock()
	cp := res
	m.sessions[sid] = &cp
	m.mu.Unlock()
	return res, nil
}

func (m *Manager) enrichSignInState(st *SignInSessionState) {
	st.UserCode = st.DeviceCode
	if st.PromptLabel == "" {
		st.PromptLabel = st.Instructions
	}
	switch st.Status {
	case "completed":
		st.Phase = "done"
	case "failed":
		st.Phase = "failed"
	default:
		switch {
		case st.DeviceCode != "" || st.Method == "auto":
			st.Phase = "device"
		case st.Method == "code":
			st.Phase = "prompt"
		case st.URL != "":
			st.Phase = "open"
		default:
			st.Phase = "starting"
		}
	}
	if st.Status == "completed" && st.AccountID != "" {
		m.mu.RLock()
		if prov, ok := m.providers[st.ProviderID]; ok {
			for i := range prov.Accounts {
				if prov.Accounts[i].ID == st.AccountID {
					acc := prov.Accounts[i]
					acc.Enabled = true
					st.Account = &acc
					break
				}
			}
		}
		m.mu.RUnlock()
	}
}

// RemoveAccount signs out and removes an account from plugin-auth.json.
func (m *Manager) RemoveAccount(ctx context.Context, providerID, accountID string) error {
	if m.runtimeMode == "bun" && m.bunHost != nil && m.bunHost.IsRunning() {
		if err := m.bunHost.Call(ctx, "signOut", map[string]any{
			"provider": providerID,
			"account":  accountID,
		}, nil); err != nil {
			return err
		}
	} else {
		if err := m.embeddedHost.RemoveAuthEntry(accountID); err != nil {
			return err
		}
	}
	return m.RefreshProviders(ctx)
}

// CheckinAccount triggers a plugin's daily check-in hook for an account.
func (m *Manager) CheckinAccount(ctx context.Context, providerID, accountID string) (PluginCheckinResult, error) {
	if m.runtimeMode == "bun" && m.bunHost != nil && m.bunHost.IsRunning() {
		var res PluginCheckinResult
		if err := m.bunHost.Call(ctx, "checkin", map[string]any{
			"provider": providerID,
			"account":  accountID,
		}, &res); err != nil {
			return PluginCheckinResult{}, err
		}
		res.At = types.NowRFC3339()
		m.mu.Lock()
		m.checkins[accountID] = &res
		m.mu.Unlock()
		_ = m.RefreshProviders(ctx)
		return res, nil
	}
	return PluginCheckinResult{}, errors.New("daily check-in requires Bun plugin runtime")
}

// RefreshQuotas queries usage/quotas for all signed-in plugin accounts that support it.
func (m *Manager) RefreshQuotas(ctx context.Context) error {
	if m.runtimeMode != "bun" || m.bunHost == nil || !m.bunHost.IsRunning() {
		return m.RefreshProviders(ctx)
	}
	m.mu.RLock()
	provs := make([]PluginProviderState, 0, len(m.providers))
	for _, p := range m.providers {
		if p.SupportsUsage && len(p.Accounts) > 0 {
			provs = append(provs, p)
		}
	}
	m.mu.RUnlock()

	for _, p := range provs {
		for _, acc := range p.Accounts {
			var u PluginUsage
			if err := m.bunHost.Call(ctx, "usage", map[string]any{
				"provider": p.ID,
				"account":  acc.ID,
			}, &u); err == nil {
				cp := u
				m.mu.Lock()
				m.quotas[acc.ID] = &cp
				m.mu.Unlock()
			}
		}
	}
	return m.RefreshProviders(ctx)
}

// HasModel implements router.PluginProviderLookup.
func (m *Manager) HasModel(providerID, modelID string) bool {
	if m == nil {
		return false
	}
	m.mu.RLock()
	defer m.mu.RUnlock()
	p, ok := m.providers[providerID]
	if !ok {
		return false
	}
	for _, mod := range p.Models {
		if mod.ID == modelID {
			return true
		}
	}
	return false
}

// FindProvidersForModel implements router.PluginProviderLookup.
func (m *Manager) FindProvidersForModel(modelID string) []string {
	if m == nil {
		return nil
	}
	m.mu.RLock()
	defer m.mu.RUnlock()
	var out []string
	for _, p := range m.providers {
		for _, mod := range p.Models {
			if mod.ID == modelID {
				out = append(out, p.ID)
				break
			}
		}
	}
	return out
}

// AllModels returns "<provider>/<model>" and raw model entries for /v1/models.
func (m *Manager) AllModels() []PluginModelInfo {
	m.mu.RLock()
	defer m.mu.RUnlock()
	var out []PluginModelInfo
	for _, p := range m.providers {
		for _, mod := range p.Models {
			cp := mod
			cp.ID = p.ID + "/" + mod.ID
			out = append(out, cp)
		}
	}
	return out
}

// ModelInfo returns the protocol, npm, apiId, and url for a plugin provider+model.
func (m *Manager) ModelInfo(providerID, modelID string) (PluginModelInfo, bool) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	p, ok := m.providers[providerID]
	if !ok {
		return PluginModelInfo{}, false
	}
	for _, mod := range p.Models {
		if mod.ID == modelID {
			if mod.Protocol == "" {
				mod.Protocol = p.Protocol
			}
			return mod, true
		}
	}
	return PluginModelInfo{ID: modelID, Protocol: p.Protocol}, true
}

// ExecuteRequest proxies an upstream completion request through a plugin provider (Bun or Embedded).
func (m *Manager) ExecuteRequest(ctx context.Context, providerID, modelID string, stream bool, body []byte, headers map[string]string) (*http.Response, types.Protocol, error) {
	minfo, _ := m.ModelInfo(providerID, modelID)
	targetProto := minfo.Protocol
	if targetProto == "" {
		targetProto = types.ProtocolOpenAI
	}
	apiModel := minfo.APIID
	if apiModel == "" {
		apiModel = modelID
	}
	relPath := translate.UpstreamPath(targetProto, apiModel, stream)

	if m.runtimeMode == "bun" && m.bunHost != nil && m.bunHost.IsRunning() {
		targetURL := relPath
		if minfo.URL != "" {
			base := strings.TrimRight(minfo.URL, "/")
			if strings.HasSuffix(base, "/v1") && strings.HasPrefix(relPath, "/v1/") {
				relPath = strings.TrimPrefix(relPath, "/v1")
			}
			targetURL = base + relPath
		}
		m.mu.RLock()
		prov := m.providers[providerID]
		m.mu.RUnlock()
		accountID := ""
		if len(prov.Accounts) > 0 {
			accountID = prov.Accounts[0].ID
		}
		resp, err := m.bunHost.Fetch(ctx, map[string]any{
			"provider": providerID,
			"account":  accountID,
			"model":    apiModel,
			"npm":      minfo.Npm,
			"url":      targetURL,
			"method":   http.MethodPost,
			"headers":  headers,
			"body":     base64.StdEncoding.EncodeToString(body),
		})
		return resp, targetProto, err
	}

	resp, err := m.embeddedHost.ExecuteRequest(ctx, providerID, "", relPath, body, headers)
	return resp, targetProto, err
}

func extractDeviceCode(instructions string) string {
	if instructions == "" {
		return ""
	}
	m := deviceCodeRe.FindStringSubmatch(instructions)
	if len(m) > 1 && m[1] != "" {
		return m[1]
	}
	if len(m) > 2 && m[2] != "" {
		return m[2]
	}
	return ""
}
