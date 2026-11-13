package plugin

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/falcon-gateway/falcon/core/internal/store"
	"github.com/falcon-gateway/falcon/core/internal/translate"
	"github.com/falcon-gateway/falcon/core/internal/types"
)

const zenFreeBaseURL = "https://opencode.ai/zen/v1"

// EmbeddedHost provides pure-Go plugin execution without fork()/exec() for iOS
// or environments without Bun.
type EmbeddedHost struct {
	mu          sync.RWMutex
	dataDir     string
	httpClient  *http.Client
	zenModels   []PluginModelInfo
	zenFetched  time.Time
	oauthStates map[string]embeddedOAuthSession
}

type embeddedOAuthSession struct {
	ProviderID   string
	AccountKey   string
	Method       string
	CodeVerifier string
	DeviceCode   string
	IntervalSec  int
	AuthURL      string
	TokenURL     string
	ClientID     string
	RedirectURI  string
}

func NewEmbeddedHost(dataDir string, client *http.Client) *EmbeddedHost {
	if client == nil {
		client = &http.Client{Timeout: 90 * time.Second}
	}
	return &EmbeddedHost{
		dataDir:     dataDir,
		httpClient:  client,
		oauthStates: make(map[string]embeddedOAuthSession),
	}
}

func (e *EmbeddedHost) AuthPath() string {
	return filepath.Join(e.dataDir, "plugin-auth.json")
}

func (e *EmbeddedHost) ReadAuth() map[string]AuthRecord {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return readAuthFile(e.AuthPath())
}

func (e *EmbeddedHost) WriteAuthEntry(key string, rec AuthRecord) error {
	e.mu.Lock()
	defer e.mu.Unlock()
	all := readAuthFile(e.AuthPath())
	all[key] = rec
	return store.WriteAtomicJSON(e.AuthPath(), all)
}

func (e *EmbeddedHost) RemoveAuthEntry(key string) error {
	e.mu.Lock()
	defer e.mu.Unlock()
	all := readAuthFile(e.AuthPath())
	delete(all, key)
	return store.WriteAtomicJSON(e.AuthPath(), all)
}

func readAuthFile(path string) map[string]AuthRecord {
	raw, err := os.ReadFile(path)
	if err != nil {
		return map[string]AuthRecord{}
	}
	var m map[string]AuthRecord
	if json.Unmarshal(raw, &m) != nil || m == nil {
		return map[string]AuthRecord{}
	}
	return m
}

func (e *EmbeddedHost) ProvidersForEntries(ctx context.Context, entries []types.InstalledPluginEntry, market []MarketItem) map[string][]PluginProviderState {
	out := make(map[string][]PluginProviderState)
	auth := e.ReadAuth()
	byPkg := make(map[string]MarketItem, len(market))
	for _, m := range market {
		byPkg[m.Package] = m
	}

	for _, ent := range entries {
		if !ent.Enabled {
			continue
		}
		pkgDir := PackageDir(e.dataDir, ent.Package)
		if _, err := os.Stat(pkgDir); err != nil {
			continue
		}
		meta := byPkg[ent.Package]
		provIDs := meta.Providers
		if len(provIDs) == 0 {
			provIDs = []string{shortPluginSlug(ent.Package)}
		}
		var states []PluginProviderState
		for _, pid := range provIDs {
			st := e.buildProviderState(ctx, pid, ent.Package, meta.Name, auth)
			states = append(states, st)
		}
		out[ent.Package] = states
	}
	return out
}

func shortPluginSlug(pkg string) string {
	if idx := strings.Index(pkg, "/"); idx >= 0 {
		pkg = pkg[idx+1:]
	}
	pkg = strings.TrimPrefix(pkg, "opencode-")
	pkg = strings.TrimSuffix(pkg, "-auth")
	return pkg
}

func (e *EmbeddedHost) buildProviderState(ctx context.Context, pid, pkg, displayName string, auth map[string]AuthRecord) PluginProviderState {
	if displayName == "" {
		displayName = pid
	}
	var accounts []PluginAccountState
	for k, rec := range auth {
		if providerOfAccountKey(k) != pid {
			continue
		}
		lbl := rec.Email
		if lbl == "" && rec.Metadata != nil {
			lbl = rec.Metadata["label"]
		}
		if lbl == "" {
			lbl = k
		}
		status := "active"
		if rec.Expires > 0 && rec.Expires < time.Now().UnixMilli() && rec.Refresh == "" {
			status = "expired"
		}
		accounts = append(accounts, PluginAccountState{
			ID:         k,
			ProviderID: pid,
			Type:       rec.Type,
			Label:      lbl,
			Status:     status,
		})
	}

	if pid == "opencode-zen-free" || strings.Contains(pkg, "opencode-zen-free") {
		models := e.discoverZenFreeModels(ctx)
		return PluginProviderState{
			ID:       "opencode-zen-free",
			Name:     "OpenCode Zen Free",
			Protocol: types.ProtocolOpenAI,
			Models:   models,
			Methods: []PluginAuthMethod{
				{Index: 0, Type: "api", Label: "OpenCode Zen Public Access", Keyless: true},
			},
			Accounts: accounts,
		}
	}

	proto := defaultProtocolForPluginProvider(pid)
	methods := defaultMethodsForPluginProvider(pid)
	return PluginProviderState{
		ID:       pid,
		Name:     displayName,
		Protocol: proto,
		Models:   defaultModelsForPluginProvider(pid, proto),
		Methods:  methods,
		Accounts: accounts,
	}
}

func (e *EmbeddedHost) discoverZenFreeModels(ctx context.Context) []PluginModelInfo {
	e.mu.RLock()
	if len(e.zenModels) > 0 && time.Since(e.zenFetched) < 10*time.Minute {
		cp := append([]PluginModelInfo{}, e.zenModels...)
		e.mu.RUnlock()
		return cp
	}
	e.mu.RUnlock()

	fallback := []PluginModelInfo{
		{ID: "big-pickle", Name: "Big Pickle (Free)", Protocol: types.ProtocolOpenAI, URL: zenFreeBaseURL, Free: true, Context: 128000, Output: 16384},
		{ID: "glm-4.7-free", Name: "GLM 4.7 Free", Protocol: types.ProtocolOpenAI, URL: zenFreeBaseURL, Free: true, Context: 128000, Output: 16384},
		{ID: "kimi-k2.5-free", Name: "Kimi K2.5 Free", Protocol: types.ProtocolOpenAI, URL: zenFreeBaseURL, Free: true, Context: 128000, Output: 16384},
		{ID: "minimax-m2.5-free", Name: "MiniMax M2.5 Free", Protocol: types.ProtocolOpenAI, URL: zenFreeBaseURL, Free: true, Context: 128000, Output: 16384},
		{ID: "gpt-5-nano", Name: "GPT-5 Nano (Free)", Protocol: types.ProtocolOpenAI, URL: zenFreeBaseURL, Free: true, Context: 128000, Output: 16384},
	}

	c, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(c, http.MethodGet, zenFreeBaseURL+"/models", nil)
	if err != nil {
		return fallback
	}
	req.Header.Set("Authorization", "Bearer public")
	resp, err := e.httpClient.Do(req)
	if err != nil {
		return fallback
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return fallback
	}
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 2<<20))
	if err != nil {
		return fallback
	}
	var parsed struct {
		Data []struct {
			ID   string `json:"id"`
			Name string `json:"name"`
		} `json:"data"`
	}
	if json.Unmarshal(raw, &parsed) != nil || len(parsed.Data) == 0 {
		return fallback
	}
	var live []PluginModelInfo
	for _, m := range parsed.Data {
		if m.ID == "" {
			continue
		}
		name := m.Name
		if name == "" {
			name = m.ID
		}
		live = append(live, PluginModelInfo{
			ID:       m.ID,
			Name:     name,
			Protocol: types.ProtocolOpenAI,
			URL:      zenFreeBaseURL,
			Free:     true,
			Context:  128000,
			Output:   16384,
		})
	}
	if len(live) == 0 {
		return fallback
	}
	e.mu.Lock()
	e.zenModels = live
	e.zenFetched = time.Now()
	e.mu.Unlock()
	return live
}

func (e *EmbeddedHost) StartSignIn(ctx context.Context, req SignInStartRequest) (SignInSessionState, error) {
	pid := req.ProviderID
	key := freshAccountKey(e.ReadAuth(), pid)
	sid := store.NewID("signin")

	if pid == "opencode-zen-free" {
		rec := AuthRecord{
			Type:     "api",
			Key:      "public",
			Metadata: map[string]string{"label": "public"},
		}
		if err := e.WriteAuthEntry(key, rec); err != nil {
			return SignInSessionState{}, err
		}
		return SignInSessionState{
			SessionID:  sid,
			ProviderID: pid,
			Status:     "completed",
			Method:     "api",
			AccountID:  key,
		}, nil
	}

	methods := defaultMethodsForPluginProvider(pid)
	method := PluginAuthMethod{Type: "api", Label: "API Key / Token"}
	if req.MethodIndex >= 0 && req.MethodIndex < len(methods) {
		method = methods[req.MethodIndex]
	}

	if method.Type == "api" || req.APIKey != "" {
		secret := strings.TrimSpace(req.APIKey)
		if secret == "" && !method.Keyless {
			return SignInSessionState{}, errors.New("API key or token is required")
		}
		if secret == "" {
			secret = "public"
		}
		rec := AuthRecord{
			Type:     "api",
			Key:      secret,
			Metadata: req.Inputs,
		}
		if err := e.WriteAuthEntry(key, rec); err != nil {
			return SignInSessionState{}, err
		}
		return SignInSessionState{
			SessionID:  sid,
			ProviderID: pid,
			Status:     "completed",
			Method:     "api",
			AccountID:  key,
		}, nil
	}

	// Pure-Go OAuth Device Flow for GitHub Copilot or PKCE URL for OAuth providers
	if pid == "github-copilot" {
		return e.startCopilotDeviceFlow(ctx, sid, pid, key)
	}

	verifier := randomBase64URL(32)
	challenge := pkceChallenge(verifier)
	authURL, tokenURL, clientID, redirectURI := oauthEndpointsForProvider(pid, challenge, sid)

	e.mu.Lock()
	e.oauthStates[sid] = embeddedOAuthSession{
		ProviderID:   pid,
		AccountKey:   key,
		Method:       "code",
		CodeVerifier: verifier,
		AuthURL:      authURL,
		TokenURL:     tokenURL,
		ClientID:     clientID,
		RedirectURI:  redirectURI,
	}
	e.mu.Unlock()

	return SignInSessionState{
		SessionID:    sid,
		ProviderID:   pid,
		Status:       "pending",
		Method:       "code",
		URL:          authURL,
		Instructions: "Open the authorization URL in your browser and paste the callback URL or authorization code.",
	}, nil
}

func (e *EmbeddedHost) startCopilotDeviceFlow(ctx context.Context, sid, pid, key string) (SignInSessionState, error) {
	form := url.Values{
		"client_id": {"Iv1.b507a08c87ecfe98"},
		"scope":     {"read:user"},
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://github.com/login/device/code", strings.NewReader(form.Encode()))
	if err != nil {
		return SignInSessionState{}, err
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := e.httpClient.Do(req)
	if err != nil {
		return SignInSessionState{}, err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	var dc struct {
		DeviceCode      string `json:"device_code"`
		UserCode        string `json:"user_code"`
		VerificationURI string `json:"verification_uri"`
		Interval        int    `json:"interval"`
		Error           string `json:"error"`
	}
	if err := json.Unmarshal(raw, &dc); err != nil {
		return SignInSessionState{}, err
	}
	if dc.DeviceCode == "" {
		return SignInSessionState{}, fmt.Errorf("device flow failed: %s", dc.Error)
	}
	if dc.Interval <= 0 {
		dc.Interval = 5
	}
	e.mu.Lock()
	e.oauthStates[sid] = embeddedOAuthSession{
		ProviderID:  pid,
		AccountKey:  key,
		Method:      "auto",
		DeviceCode:  dc.DeviceCode,
		IntervalSec: dc.Interval,
	}
	e.mu.Unlock()
	return SignInSessionState{
		SessionID:    sid,
		ProviderID:   pid,
		Status:       "pending",
		Method:       "auto",
		URL:          dc.VerificationURI,
		DeviceCode:   dc.UserCode,
		Instructions: fmt.Sprintf("Enter code %s at %s", dc.UserCode, dc.VerificationURI),
	}, nil
}

func (e *EmbeddedHost) CompleteCallback(ctx context.Context, sid, codeOrURL string) (SignInSessionState, error) {
	e.mu.RLock()
	sess, ok := e.oauthStates[sid]
	e.mu.RUnlock()
	if !ok {
		return SignInSessionState{}, errors.New("sign-in session not found")
	}
	if sess.Method == "auto" && sess.ProviderID == "github-copilot" {
		form := url.Values{
			"client_id":   {"Iv1.b507a08c87ecfe98"},
			"device_code": {sess.DeviceCode},
			"grant_type":  {"urn:ietf:params:oauth:grant-type:device_code"},
		}
		req, _ := http.NewRequestWithContext(ctx, http.MethodPost, "https://github.com/login/oauth/access_token", strings.NewReader(form.Encode()))
		req.Header.Set("Accept", "application/json")
		req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		resp, err := e.httpClient.Do(req)
		if err != nil {
			return SignInSessionState{}, err
		}
		defer resp.Body.Close()
		var tok struct {
			AccessToken string `json:"access_token"`
			Error       string `json:"error"`
		}
		_ = json.NewDecoder(resp.Body).Decode(&tok)
		if tok.AccessToken == "" {
			if tok.Error == "authorization_pending" || tok.Error == "slow_down" {
				return SignInSessionState{SessionID: sid, ProviderID: sess.ProviderID, Status: "pending", Method: "auto"}, nil
			}
			return SignInSessionState{SessionID: sid, ProviderID: sess.ProviderID, Status: "failed", Error: tok.Error}, nil
		}
		e.mu.Lock()
		delete(e.oauthStates, sid)
		e.mu.Unlock()
		_ = e.WriteAuthEntry(sess.AccountKey, AuthRecord{Type: "oauth", Refresh: tok.AccessToken, Access: tok.AccessToken})
		return SignInSessionState{SessionID: sid, ProviderID: sess.ProviderID, Status: "completed", AccountID: sess.AccountKey}, nil
	}

	code := extractAuthCode(codeOrURL)
	if code == "" {
		return SignInSessionState{}, errors.New("authorization code is required")
	}
	e.mu.Lock()
	delete(e.oauthStates, sid)
	e.mu.Unlock()

	if sess.TokenURL != "" {
		form := url.Values{
			"grant_type":    {"authorization_code"},
			"code":          {code},
			"client_id":     {sess.ClientID},
			"redirect_uri":  {sess.RedirectURI},
			"code_verifier": {sess.CodeVerifier},
		}
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, sess.TokenURL, strings.NewReader(form.Encode()))
		if err == nil {
			req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
			req.Header.Set("Accept", "application/json")
			if resp, rerr := e.httpClient.Do(req); rerr == nil {
				defer resp.Body.Close()
				var tok struct {
					AccessToken  string `json:"access_token"`
					RefreshToken string `json:"refresh_token"`
					ExpiresIn    int64  `json:"expires_in"`
				}
				if json.NewDecoder(resp.Body).Decode(&tok) == nil && tok.AccessToken != "" {
					var exp int64
					if tok.ExpiresIn > 0 {
						exp = time.Now().Add(time.Duration(tok.ExpiresIn) * time.Second).UnixMilli()
					}
					_ = e.WriteAuthEntry(sess.AccountKey, AuthRecord{
						Type:    "oauth",
						Access:  tok.AccessToken,
						Refresh: tok.RefreshToken,
						Expires: exp,
					})
					return SignInSessionState{SessionID: sid, ProviderID: sess.ProviderID, Status: "completed", AccountID: sess.AccountKey}, nil
				}
			}
		}
	}

	// Fallback: persist pasted token/code as API credential if token exchange endpoint isn't configured
	if err := e.WriteAuthEntry(sess.AccountKey, AuthRecord{Type: "api", Key: code}); err != nil {
		return SignInSessionState{}, err
	}
	return SignInSessionState{SessionID: sid, ProviderID: sess.ProviderID, Status: "completed", AccountID: sess.AccountKey}, nil
}

// ExecuteRequest proxies a gateway HTTP request using pure-Go net/http in embedded mode.
func (e *EmbeddedHost) ExecuteRequest(ctx context.Context, providerID, accountID, relPath string, body []byte, headers map[string]string) (*http.Response, error) {
	auth := e.ReadAuth()
	key := accountID
	if key == "" {
		for k := range auth {
			if providerOfAccountKey(k) == providerID {
				key = k
				break
			}
		}
	}
	rec, ok := auth[key]
	if !ok && providerID == "opencode-zen-free" {
		rec = AuthRecord{Type: "api", Key: "public"}
		ok = true
	}
	if !ok {
		return nil, fmt.Errorf("provider %s is not signed in", providerID)
	}

	baseURL := baseURLForPluginProvider(providerID)
	if baseURL == "" {
		return nil, fmt.Errorf("no upstream endpoint mapped for embedded plugin provider %s", providerID)
	}
	if !strings.HasPrefix(relPath, "/") {
		relPath = "/" + relPath
	}
	if strings.HasSuffix(baseURL, "/v1") && strings.HasPrefix(relPath, "/v1/") {
		relPath = strings.TrimPrefix(relPath, "/v1")
	}
	targetURL := strings.TrimRight(baseURL, "/") + relPath

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, targetURL, strings.NewReader(string(body)))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	token := rec.Access
	if token == "" {
		token = rec.Key
	}
	if token != "" {
		proto := defaultProtocolForPluginProvider(providerID)
		switch proto {
		case types.ProtocolAnthropic:
			req.Header.Set("x-api-key", token)
			req.Header.Set("anthropic-version", "2023-06-01")
		case types.ProtocolGemini:
			req.Header.Set("x-goog-api-key", token)
		default:
			req.Header.Set("Authorization", "Bearer "+token)
		}
	}
	return e.httpClient.Do(req)
}

func providerOfAccountKey(k string) string {
	if idx := strings.IndexByte(k, '#'); idx >= 0 {
		return k[:idx]
	}
	return k
}

func freshAccountKey(auth map[string]AuthRecord, providerID string) string {
	if _, exists := auth[providerID]; !exists {
		return providerID
	}
	for i := 2; ; i++ {
		cand := fmt.Sprintf("%s#%d", providerID, i)
		if _, exists := auth[cand]; !exists {
			return cand
		}
	}
}

func baseURLForPluginProvider(pid string) string {
	switch pid {
	case "opencode-zen-free":
		return zenFreeBaseURL
	case "github-copilot":
		return "https://api.githubcopilot.com"
	case "anthropic":
		return "https://api.anthropic.com/v1"
	case "openai":
		return "https://api.openai.com/v1"
	case "google":
		return "https://generativelanguage.googleapis.com/v1beta"
	case "qwen":
		return "https://dashscope.aliyuncs.com/compatible-mode/v1"
	case "kimi":
		return "https://api.moonshot.cn/v1"
	case "glm":
		return "https://open.bigmodel.cn/api/paas/v4"
	case "minimax":
		return "https://api.minimaxi.com/v1"
	case "deepseek-web":
		return "https://api.deepseek.com/v1"
	case "doubao":
		return "https://ark.cn-beijing.volces.com/api/v3"
	default:
		return ""
	}
}

func defaultProtocolForPluginProvider(pid string) types.Protocol {
	switch pid {
	case "anthropic":
		return types.ProtocolAnthropic
	case "google":
		return types.ProtocolGemini
	default:
		return types.ProtocolOpenAI
	}
}

func defaultMethodsForPluginProvider(pid string) []PluginAuthMethod {
	switch pid {
	case "opencode-zen-free":
		return []PluginAuthMethod{{Index: 0, Type: "api", Label: "OpenCode Zen Public Access", Keyless: true}}
	case "github-copilot":
		return []PluginAuthMethod{{Index: 0, Type: "oauth", Label: "GitHub OAuth Device Flow"}}
	case "anthropic", "openai", "google":
		return []PluginAuthMethod{
			{Index: 0, Type: "oauth", Label: "OAuth Sign-In"},
			{Index: 1, Type: "api", Label: "API Key / Token", Placeholder: "sk-..."},
		}
	default:
		return []PluginAuthMethod{
			{Index: 0, Type: "api", Label: "API Key / Session Token", Placeholder: "Enter token or API key"},
		}
	}
}

func defaultModelsForPluginProvider(pid string, proto types.Protocol) []PluginModelInfo {
	switch pid {
	case "github-copilot":
		return []PluginModelInfo{
			{ID: "gpt-4o", Name: "GPT-4o", Protocol: proto},
			{ID: "claude-sonnet-4", Name: "Claude Sonnet 4", Protocol: proto},
		}
	case "anthropic":
		return []PluginModelInfo{
			{ID: "claude-sonnet-4-5", Name: "Claude Sonnet 4.5", Protocol: proto},
		}
	case "openai":
		return []PluginModelInfo{
			{ID: "gpt-4.1", Name: "GPT-4.1", Protocol: proto},
			{ID: "o3-mini", Name: "o3-mini", Protocol: proto},
		}
	case "google":
		return []PluginModelInfo{
			{ID: "gemini-2.5-flash", Name: "Gemini 2.5 Flash", Protocol: proto},
			{ID: "gemini-2.5-pro", Name: "Gemini 2.5 Pro", Protocol: proto},
		}
	default:
		return []PluginModelInfo{}
	}
}

func oauthEndpointsForProvider(pid, challenge, state string) (authURL, tokenURL, clientID, redirectURI string) {
	switch pid {
	case "anthropic":
		redirectURI = "https://console.anthropic.com/oauth/code/callback"
		clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
		tokenURL = "https://console.anthropic.com/v1/oauth/token"
		q := url.Values{
			"code":                  {"true"},
			"client_id":             {clientID},
			"response_type":         {"code"},
			"redirect_uri":          {redirectURI},
			"scope":                 {"org:create_api_key user:profile user:inference"},
			"code_challenge":        {challenge},
			"code_challenge_method": {"S256"},
			"state":                 {state},
		}
		authURL = "https://claude.ai/oauth/authorize?" + q.Encode()
		return
	case "openai":
		redirectURI = "http://localhost:1455/auth/callback"
		clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
		tokenURL = "https://auth.openai.com/oauth/token"
		q := url.Values{
			"response_type":         {"code"},
			"client_id":             {clientID},
			"redirect_uri":          {redirectURI},
			"scope":                 {"openid profile email offline_access"},
			"code_challenge":        {challenge},
			"code_challenge_method": {"S256"},
			"state":                 {state},
		}
		authURL = "https://auth.openai.com/oauth/authorize?" + q.Encode()
		return
	default:
		return "", "", "", ""
	}
}

func randomBase64URL(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return base64.RawURLEncoding.EncodeToString(b)
}

func pkceChallenge(verifier string) string {
	sum := sha256.Sum256([]byte(verifier))
	return base64.RawURLEncoding.EncodeToString(sum[:])
}

func extractAuthCode(input string) string {
	input = strings.TrimSpace(input)
	if input == "" {
		return ""
	}
	if strings.Contains(input, "://") || strings.Contains(input, "code=") {
		if u, err := url.Parse(input); err == nil {
			if c := u.Query().Get("code"); c != "" {
				if idx := strings.IndexByte(c, '#'); idx >= 0 {
					c = c[:idx]
				}
				return c
			}
		}
	}
	if idx := strings.IndexByte(input, '#'); idx >= 0 {
		return input[:idx]
	}
	return input
}

// Ensure translate package import is used if needed for URL path helpers
var _ = translate.UpstreamPath
