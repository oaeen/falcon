package plugin

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha512"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/falcon-gateway/falcon/core/internal/store"
	"github.com/falcon-gateway/falcon/core/internal/types"
)

func buildTestTgz(t *testing.T, files map[string]string) ([]byte, string) {
	t.Helper()
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	for name, content := range files {
		hdr := &tar.Header{
			Name: "package/" + name,
			Mode: 0o644,
			Size: int64(len(content)),
		}
		if err := tw.WriteHeader(hdr); err != nil {
			t.Fatal(err)
		}
		if _, err := tw.Write([]byte(content)); err != nil {
			t.Fatal(err)
		}
	}
	if err := tw.Close(); err != nil {
		t.Fatal(err)
	}
	if err := gz.Close(); err != nil {
		t.Fatal(err)
	}
	raw := buf.Bytes()
	sum := sha512.Sum512(raw)
	integrity := "sha512-" + base64.StdEncoding.EncodeToString(sum[:])
	return raw, integrity
}

func TestBuiltinMarketHasRequiredPlugins(t *testing.T) {
	items := BuiltinMarket()
	if len(items) < 15 {
		t.Fatalf("expected at least 15 market plugins, got %d", len(items))
	}
	required := []string{
		"@magpie-community/opencode-zen-free-auth",
		"opencode-copilot-auth",
		"opencode-gemini-auth",
		"opencode-anthropic-auth",
		"opencode-openai-codex-auth",
		"opencode-qwen-auth",
		"opencode-deepseek-web-auth",
		"opencode-kimi-auth",
		"opencode-glm-auth",
		"opencode-minimax-auth",
		"opencode-doubao-auth",
		"@magpie-community/opencode-cursor-auth",
		"opencode-windsurf-auth",
		"opencode-trae-auth",
		"@magpie-community/opencode-workbuddy-auth",
	}
	have := make(map[string]bool)
	for _, it := range items {
		have[it.Package] = true
		if it.SummaryZh == "" || it.SummaryEn == "" {
			t.Fatalf("plugin %s missing bilingual summary", it.Package)
		}
	}
	for _, req := range required {
		if !have[req] {
			t.Fatalf("missing required plugin in market.json: %s", req)
		}
	}
}

func TestDistInstallAndSHA512Verification(t *testing.T) {
	tgzBytes, integrity := buildTestTgz(t, map[string]string{
		"package.json": `{"name":"@magpie-community/opencode-zen-free-auth","version":"1.0.3","main":"index.js"}`,
		"index.js":     `export default { id: "zen", server: async () => ({}) };`,
	})

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/index.json":
			idx := map[string]any{
				"packages": map[string]any{
					"@magpie-community/opencode-zen-free-auth": map[string]any{
						"latest": "1.0.3",
						"versions": map[string]any{
							"1.0.3": map[string]any{
								"file":      "tgz/opencode-zen-free-auth-1.0.3.tgz",
								"integrity": integrity,
							},
						},
					},
				},
			}
			_ = json.NewEncoder(w).Encode(idx)
		case "/tgz/opencode-zen-free-auth-1.0.3.tgz":
			_, _ = w.Write(tgzBytes)
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer srv.Close()

	prevRaw, prevJSD := distBaseRaw, distBaseJsDelivr
	distBaseRaw = srv.URL
	distBaseJsDelivr = srv.URL
	defer func() {
		distBaseRaw, distBaseJsDelivr = prevRaw, prevJSD
	}()

	dataDir := t.TempDir()
	res, err := InstallPackage(context.Background(), srv.Client(), dataDir, "@magpie-community/opencode-zen-free-auth", true, "")
	if err != nil {
		t.Fatalf("InstallPackage failed: %v", err)
	}
	if res.Version != "1.0.3" || res.Source != "dist" {
		t.Fatalf("unexpected InstallResult: %+v", res)
	}
	if InstalledVersion(dataDir, "@magpie-community/opencode-zen-free-auth") != "1.0.3" {
		t.Fatal("InstalledVersion did not read extracted package.json")
	}

	// Verify bad SHA-512 fails
	if err := VerifyIntegrity(tgzBytes, "sha512-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==", ""); err == nil {
		t.Fatal("expected SHA-512 mismatch error")
	}
}

func TestEmbeddedHostZenFreeFallback(t *testing.T) {
	dataDir := t.TempDir()
	pkgDir := PackageDir(dataDir, "@magpie-community/opencode-zen-free-auth")
	if err := os.MkdirAll(pkgDir, 0o755); err != nil {
		t.Fatal(err)
	}
	_ = os.WriteFile(filepath.Join(pkgDir, "package.json"), []byte(`{"name":"@magpie-community/opencode-zen-free-auth","version":"1.0.0"}`), 0o644)

	st, err := store.Open(dataDir)
	if err != nil {
		t.Fatal(err)
	}
	_ = st.UpsertPluginEntry(types.InstalledPluginEntry{
		Package: "@magpie-community/opencode-zen-free-auth",
		Spec:    "@magpie-community/opencode-zen-free-auth",
		Enabled: true,
	})

	// Pass invalid bun path so Manager runs in embedded mode
	mgr := NewManager(st, "/nonexistent/bun-binary", t.TempDir(), "", "", nil)
	if mgr.RuntimeMode() != "embedded" {
		t.Fatalf("expected embedded mode when bun missing, got %s", mgr.RuntimeMode())
	}
	if err := mgr.Reload(context.Background()); err != nil {
		t.Fatal(err)
	}
	sess, err := mgr.StartSignIn(context.Background(), SignInStartRequest{
		ProviderID:  "opencode-zen-free",
		MethodIndex: 0,
	})
	if err != nil || sess.Status != "completed" {
		t.Fatalf("embedded Zen sign-in failed: sess=%+v err=%v", sess, err)
	}
	if !mgr.HasModel("opencode-zen-free", "big-pickle") {
		t.Fatal("expected opencode-zen-free fallback model big-pickle to be available")
	}
}

func TestBunHostRPCAndStreamingFetch(t *testing.T) {
	bun := DetectBun("")
	if bun == "" {
		t.Skip("bun not installed in environment; skipping BunHost RPC integration test")
	}

	// Mock upstream LLM server
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer test-plugin-token" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		w.Header().Set("Content-Type", "text/event-stream")
		_, _ = w.Write([]byte("data: {\"id\":\"1\",\"choices\":[{\"delta\":{\"content\":\"hi\"}}]}\n\n"))
		_, _ = w.Write([]byte("data: [DONE]\n\n"))
	}))
	defer upstream.Close()

	dataDir := t.TempDir()
	pkgDir := PackageDir(dataDir, "mock-opencode-plugin")
	if err := os.MkdirAll(pkgDir, 0o755); err != nil {
		t.Fatal(err)
	}
	_ = os.WriteFile(filepath.Join(pkgDir, "package.json"), []byte(`{"name":"mock-opencode-plugin","version":"1.0.0","main":"index.mjs"}`), 0o644)
	pluginJS := `
export default async function(input) {
  return {
    config: async (cfg) => {
      cfg.provider = cfg.provider || {};
      cfg.provider["mock-prov"] = {
        name: "Mock Provider",
        api: "` + upstream.URL + `/v1",
        npm: "@ai-sdk/openai-compatible",
        models: {
          "mock-free": { id: "mock-free", name: "Mock Free", free: true }
        }
      };
    },
    auth: {
      provider: "mock-prov",
      methods: [{
        type: "api",
        label: "Instant Mock",
        keyless: true,
        authorize: async () => ({ type: "success", key: "test-plugin-token" })
      }],
      loader: async (getAuth) => {
        const a = await getAuth();
        return { baseURL: "` + upstream.URL + `/v1", apiKey: a?.key || "" };
      }
    }
  };
}
`
	_ = os.WriteFile(filepath.Join(pkgDir, "index.mjs"), []byte(pluginJS), 0o644)

	st, err := store.Open(dataDir)
	if err != nil {
		t.Fatal(err)
	}
	_ = st.UpsertPluginEntry(types.InstalledPluginEntry{
		Package: "mock-opencode-plugin",
		Spec:    "mock-opencode-plugin",
		Enabled: true,
	})

	mgr := NewManager(st, bun, t.TempDir(), "", "", nil)
	defer mgr.Stop()
	if mgr.RuntimeMode() != "bun" {
		t.Fatalf("expected bun runtimeMode, got %s", mgr.RuntimeMode())
	}
	if err := mgr.Reload(context.Background()); err != nil {
		t.Fatalf("Reload failed: %v", err)
	}
	if !mgr.HasModel("mock-prov", "mock-free") {
		t.Fatalf("expected mock-prov/mock-free in plugin models, state=%+v", mgr.StatePlugins())
	}

	sess, err := mgr.StartSignIn(context.Background(), SignInStartRequest{
		ProviderID:  "mock-prov",
		MethodIndex: 0,
	})
	if err != nil || sess.Status != "completed" {
		t.Fatalf("BunHost StartSignIn failed: sess=%+v err=%v", sess, err)
	}

	resp, proto, err := mgr.ExecuteRequest(context.Background(), "mock-prov", "mock-free", true, []byte(`{"model":"mock-free","messages":[{"role":"user","content":"hi"}],"stream":true}`), nil)
	if err != nil {
		t.Fatalf("ExecuteRequest failed: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 || proto != types.ProtocolOpenAI {
		t.Fatalf("unexpected response status=%d proto=%s", resp.StatusCode, proto)
	}
	raw, _ := io.ReadAll(resp.Body)
	if !strings.Contains(string(raw), `"content":"hi"`) {
		t.Fatalf("unexpected stream body: %s", string(raw))
	}
}

func TestCanonicalPluginDedup(t *testing.T) {
	if got := CanonicalPluginPackage("opencode-workbuddy-auth"); got != "@magpie-community/opencode-workbuddy-auth" {
		t.Fatalf("expected canonical workbuddy, got %s", got)
	}
	if got := CanonicalPluginPackage("workbuddy"); got != "@magpie-community/opencode-workbuddy-auth" {
		t.Fatalf("expected canonical workbuddy from short slug, got %s", got)
	}
	if got := CanonicalPluginPackage("opencode-cursor-auth"); got != "@magpie-community/opencode-cursor-auth" {
		t.Fatalf("expected canonical cursor, got %s", got)
	}

	// Mock remote registry containing overlapping scoped + bare entries + middleware
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{
			"version": 1,
			"plugins": []map[string]any{
				{
					"package":   "@magpie-community/opencode-workbuddy-auth",
					"name":      "WorkBuddy",
					"replaces":  "opencode-workbuddy-auth",
					"providers": []string{"workbuddy", "workbuddy-ai"},
				},
				{
					"package":   "opencode-workbuddy-auth",
					"name":      "WorkBuddy Legacy",
					"providers": []string{"workbuddy"},
				},
				{
					"package": "@magpie-community/middleware-word-guard",
					"name":    "Word Guard",
					"kind":    "middleware",
				},
			},
		})
	}))
	defer srv.Close()

	prevRaw, prevJsd := registryRaw, registryJsDelivr
	registryRaw, registryJsDelivr = srv.URL, srv.URL
	defer func() {
		registryRaw, registryJsDelivr = prevRaw, prevJsd
	}()

	items := FetchLiveMarket(context.Background(), srv.Client(), false)
	wbCount := 0
	for _, it := range items {
		if strings.Contains(it.Package, "workbuddy") {
			wbCount++
			if it.Package != "@magpie-community/opencode-workbuddy-auth" {
				t.Fatalf("expected canonical workbuddy package, got %s", it.Package)
			}
		}
		if strings.Contains(it.Package, "middleware") {
			t.Fatalf("did not expect middleware package in provider market: %s", it.Package)
		}
	}
	if wbCount != 1 {
		t.Fatalf("expected exactly 1 workbuddy market item, got %d", wbCount)
	}

	// Simulate legacy config.json + legacy node_modules/opencode-workbuddy-auth duplicate on disk
	dataDir := t.TempDir()
	legacyDir := PackageDir(dataDir, "opencode-workbuddy-auth")
	if err := os.MkdirAll(legacyDir, 0o755); err != nil {
		t.Fatal(err)
	}
	_ = os.WriteFile(filepath.Join(legacyDir, "package.json"), []byte(`{"name":"opencode-workbuddy-auth","version":"0.2.35","main":"index.mjs"}`), 0o644)
	_ = os.WriteFile(filepath.Join(legacyDir, "index.mjs"), []byte(`export default async () => ({});`), 0o644)

	st, err := store.Open(dataDir)
	if err != nil {
		t.Fatal(err)
	}
	_ = st.SetPluginsList([]types.InstalledPluginEntry{
		{Package: "opencode-workbuddy-auth", Spec: "opencode-workbuddy-auth", Enabled: true},
		{Package: "@magpie-community/opencode-workbuddy-auth", Spec: "@magpie-community/opencode-workbuddy-auth", Enabled: false},
	})

	mgr := NewManager(st, "/nonexistent/bun", t.TempDir(), "", "", nil)
	if err := mgr.Reload(context.Background()); err != nil {
		t.Fatal(err)
	}
	statePlugins := mgr.StatePlugins()
	if len(statePlugins) != 1 || statePlugins[0].Package != "@magpie-community/opencode-workbuddy-auth" || !statePlugins[0].Enabled {
		t.Fatalf("expected single reconciled canonical workbuddy plugin, got %+v", statePlugins)
	}
	if statePlugins[0].Version != "0.2.35" {
		t.Fatalf("expected migrated directory version 0.2.35, got %q", statePlugins[0].Version)
	}
	if _, err := os.Stat(legacyDir); !os.IsNotExist(err) {
		t.Fatalf("expected legacy directory %s to be migrated away", legacyDir)
	}
	mkt := mgr.Market(context.Background())
	installedWB := 0
	for _, it := range mkt {
		if strings.Contains(it.Package, "workbuddy") {
			installedWB++
			if !it.Installed || it.Package != "@magpie-community/opencode-workbuddy-auth" {
				t.Fatalf("expected canonical installed market row, got %+v", it)
			}
		}
	}
	if installedWB != 1 {
		t.Fatalf("expected exactly 1 workbuddy entry in Manager.Market(), got %d", installedWB)
	}
}

func TestWorkBuddyEditionsAndSelectedModels(t *testing.T) {
	bun := DetectBun("")
	if bun == "" {
		t.Skip("bun not installed in environment; skipping WorkBuddy plugin integration test")
	}

	var repairCalls int
	var seenHeaders http.Header
	var seenURL string
	mockWB := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v2/plugin/accounts":
			repairCalls++
			if r.Header.Get("Authorization") != "Bearer seed-access-tok" {
				w.WriteHeader(http.StatusUnauthorized)
				return
			}
			_ = json.NewEncoder(w).Encode(map[string]any{
				"accounts": []map[string]any{
					{
						"uid":            "u-repaired-99",
						"enterpriseId":   "ent-cn-42",
						"enterpriseName": "Acme Edu",
						"nickname":       "Alice",
						"lastLogin":      true,
					},
				},
			})
		case "/v2/chat/completions":
			seenHeaders = r.Header.Clone()
			seenURL = r.URL.Path
			w.Header().Set("Content-Type", "text/event-stream")
			_, _ = w.Write([]byte("data: {\"id\":\"wb-1\",\"model\":\"glm-5.3\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"CN OK\"}}]}\n\n"))
			_, _ = w.Write([]byte("data: {\"id\":\"wb-1\",\"model\":\"glm-5.3\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":2,\"total_tokens\":7}}\n\n"))
			_, _ = w.Write([]byte("data: [DONE]\n\n"))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer mockWB.Close()

	t.Setenv("FALCON_MOBILE", "1")
	t.Setenv("FALCON_WORKBUDDY_ENDPOINT", mockWB.URL)

	dataDir := t.TempDir()
	// Pre-populate legacy incomplete WorkBuddy OAuth auth missing uid and enterpriseId
	_ = store.WriteAtomicJSON(filepath.Join(dataDir, "plugin-auth.json"), map[string]any{
		"workbuddy": map[string]any{
			"type":    "oauth",
			"refresh": "seed-refresh-tok",
			"access":  "seed-access-tok",
			"expires": time.Now().Add(time.Hour).UnixMilli(),
		},
	})

	pkgDir := PackageDir(dataDir, "@magpie-community/opencode-workbuddy-auth")
	if err := os.MkdirAll(pkgDir, 0o755); err != nil {
		t.Fatal(err)
	}
	_ = os.WriteFile(filepath.Join(pkgDir, "package.json"), []byte(`{"name":"@magpie-community/opencode-workbuddy-auth","version":"0.2.35","main":"index.mjs"}`), 0o644)
	wbJS := `
export const WorkBuddyAIAuthPlugin = async () => ({
  config: async (cfg) => {
    cfg.provider = cfg.provider || {};
    cfg.provider["workbuddy-ai"] = {
      name: "WorkBuddy AI",
      npm: "@ai-sdk/openai-compatible",
      models: {
        "glm-5.0": { id: "glm-5.0", name: "GLM-5.0", limit: { context: 128000, output: 8192 }, free: true }
      }
    };
  },
  auth: {
    provider: "workbuddy-ai",
    methods: [
      { type: "oauth", label: "WorkBuddy AI account (browser)", authorize: async () => ({ url: "https://www.workbuddy.ai/login", method: "auto", callback: async () => ({ type: "success", refresh: "r", access: "a", expires: 9999999999999 }) }) },
      { type: "oauth", label: "WorkBuddy AI desktop's sign-in", authorize: async () => ({ type: "failed", error: "desktop" }) },
      { type: "api", label: "WorkBuddy AI API key", placeholder: "sk-wb" }
    ]
  }
});

export const WorkBuddyAuthPlugin = async () => ({
  "chat.headers": async (input, output) => {
    output.headers["X-Conversation-ID"] = String(input?.sessionID || "conv-fallback");
  },
  config: async (cfg) => {
    cfg.provider = cfg.provider || {};
    cfg.provider["workbuddy"] = {
      name: "WorkBuddy",
      npm: "@ai-sdk/openai-compatible",
      models: {
        "glm-5.3": { id: "glm-5.3", name: "GLM-5.3", limit: { context: 200000, output: 16384 }, free: true },
        "deepseek-v4": { id: "deepseek-v4", name: "DeepSeek V4", limit: { context: 128000, output: 8192 }, free: false }
      }
    };
  },
  provider: {
    id: "workbuddy",
    models: async (prov, { auth }) => {
      if (!auth?.uid) return {};
      return {
        "glm-5.3": { id: "glm-5.3", providerID: "workbuddy", name: "GLM-5.3", api: { id: "glm-5.3", url: "` + mockWB.URL + `/v2", npm: "@ai-sdk/openai-compatible" }, limit: { context: 200000, output: 16384 }, free: true },
        "deepseek-v4": { id: "deepseek-v4", providerID: "workbuddy", name: "DeepSeek V4", api: { id: "deepseek-v4", url: "` + mockWB.URL + `/v2", npm: "@ai-sdk/openai-compatible" }, limit: { context: 128000, output: 8192 }, free: false }
      };
    }
  },
  auth: {
    provider: "workbuddy",
    methods: [
      {
        type: "oauth",
        label: "WorkBuddy account (browser)",
        authorize: async () => ({
          url: "https://copilot.tencent.com/auth",
          instructions: "Sign in to WorkBuddy in the browser; this finishes by itself.",
          method: "auto",
          callback: async () => ({
            type: "success",
            refresh: "oauth-r2",
            access: "oauth-a2",
            expires: 9999999999999,
            accountId: "Bob · TeamX",
            uid: "u-bob-2",
            domain: "copilot.tencent.com",
            enterpriseId: "ent-teamx"
          })
        })
      },
      { type: "oauth", label: "WorkBuddy desktop's sign-in", authorize: async () => ({ type: "failed", error: "desktop" }) },
      { type: "api", label: "WorkBuddy API key", placeholder: "workbuddy.cn/profile/keys" }
    ],
    loader: async (getAuth) => {
      const a = await getAuth();
      return {
        baseURL: "",
        apiKey: "",
        fetch: async (input, init) => {
          const h = new Headers(init?.headers);
          h.set("X-User-Id", a?.uid || "");
          h.set("X-Enterprise-Id", a?.enterpriseId || "");
          return fetch(input, { ...init, headers: h });
        }
      };
    }
  }
});
`
	_ = os.WriteFile(filepath.Join(pkgDir, "index.mjs"), []byte(wbJS), 0o644)

	st, err := store.Open(dataDir)
	if err != nil {
		t.Fatal(err)
	}
	_ = st.UpsertPluginEntry(types.InstalledPluginEntry{
		Package: "@magpie-community/opencode-workbuddy-auth",
		Spec:    "@magpie-community/opencode-workbuddy-auth",
		Enabled: true,
	})

	mgr := NewManager(st, bun, t.TempDir(), "", "", nil)
	defer mgr.Stop()
	if err := mgr.Reload(context.Background()); err != nil {
		t.Fatalf("Reload failed: %v", err)
	}

	if repairCalls == 0 {
		t.Fatal("expected repairWorkBuddyAuth to query /v2/plugin/accounts")
	}

	// Verify persisted plugin-auth.json was repaired non-destructively
	rawAuth, _ := os.ReadFile(filepath.Join(dataDir, "plugin-auth.json"))
	if !strings.Contains(string(rawAuth), `"uid": "u-repaired-99"`) || !strings.Contains(string(rawAuth), `"enterpriseId": "ent-cn-42"`) || !strings.Contains(string(rawAuth), `"access": "seed-access-tok"`) {
		t.Fatalf("expected repaired uid/enterpriseId preserving access token, got:\n%s", string(rawAuth))
	}

	// Verify WorkBuddy CN sorts ahead of WorkBuddy AI, desktop method is filtered on mobile keeping index 2, and discovered models exist
	plugins := mgr.StatePlugins()
	if len(plugins) != 1 || len(plugins[0].Providers) != 2 {
		t.Fatalf("expected 1 plugin with 2 providers, got %+v", plugins)
	}
	if plugins[0].Providers[0].ID != "workbuddy" || plugins[0].Providers[1].ID != "workbuddy-ai" {
		t.Fatalf("expected workbuddy ahead of workbuddy-ai, got %s, %s", plugins[0].Providers[0].ID, plugins[0].Providers[1].ID)
	}
	wbProv := plugins[0].Providers[0]
	if !wbProv.Authenticated || wbProv.AccountCount != 1 {
		t.Fatalf("expected authenticated workbuddy account, got %+v", wbProv)
	}
	if len(wbProv.Methods) != 2 || wbProv.Methods[0].Index != 0 || wbProv.Methods[1].Index != 2 {
		t.Fatalf("expected mobile filtered methods keeping indices [0, 2], got %+v", wbProv.Methods)
	}

	// Test Model Selection subset filtering
	if err := mgr.SetSelectedModels("@magpie-community/opencode-workbuddy-auth", "workbuddy", []string{"glm-5.3"}); err != nil {
		t.Fatal(err)
	}
	if !mgr.HasModel("workbuddy", "glm-5.3") || mgr.HasModel("workbuddy", "deepseek-v4") {
		t.Fatal("expected workbuddy SelectedModels to filter HasModel")
	}
	plugins = mgr.StatePlugins()
	if len(plugins[0].Providers[0].Models) != 2 {
		t.Fatalf("expected providerDetails.models to keep all 2 discovered models, got %d", len(plugins[0].Providers[0].Models))
	}
	if len(plugins[0].Providers[0].SelectedModels) != 1 || plugins[0].Providers[0].SelectedModels[0] != "glm-5.3" {
		t.Fatalf("unexpected selectedModels: %+v", plugins[0].Providers[0].SelectedModels)
	}

	// Execute live request against /v2/chat/completions verifying repaired uid/enterpriseId & chat.headers
	resp, _, err := mgr.ExecuteRequest(context.Background(), "workbuddy", "glm-5.3", false, []byte(`{"model":"glm-5.3","messages":[{"role":"user","content":"hi"}],"stream":false}`), map[string]string{"content-type": "application/json"})
	if err != nil {
		t.Fatalf("ExecuteRequest workbuddy failed: %v", err)
	}
	_, _ = io.ReadAll(resp.Body)
	resp.Body.Close()
	if seenURL != "/v2/chat/completions" {
		t.Fatalf("expected /v2/chat/completions, got %s", seenURL)
	}
	if seenHeaders.Get("X-User-Id") != "u-repaired-99" || seenHeaders.Get("X-Enterprise-Id") != "ent-cn-42" || seenHeaders.Get("X-Conversation-ID") == "" {
		t.Fatalf("missing expected WorkBuddy headers: %+v", seenHeaders)
	}

	// Test OAuth browser sign-in phase == "open_auto" & full OAuth field preservation
	oauthSess, err := mgr.StartSignIn(context.Background(), SignInStartRequest{
		ProviderID:  "workbuddy",
		MethodIndex: 0,
	})
	if err != nil {
		t.Fatalf("StartSignIn oauth failed: %v", err)
	}
	if oauthSess.Phase != "open_auto" {
		t.Fatalf("expected Phase=open_auto for browser auto sign-in, got %q", oauthSess.Phase)
	}
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		polled, _ := mgr.GetSignInSession(context.Background(), oauthSess.SessionID)
		if polled.Status == "completed" {
			break
		}
		time.Sleep(25 * time.Millisecond)
	}
	rawAuthAfter, _ := os.ReadFile(filepath.Join(dataDir, "plugin-auth.json"))
	if !strings.Contains(string(rawAuthAfter), `"uid": "u-bob-2"`) || !strings.Contains(string(rawAuthAfter), `"enterpriseId": "ent-teamx"`) {
		t.Fatalf("expected callback OAuth fields preserved in plugin-auth.json, got:\n%s", string(rawAuthAfter))
	}

	// Test MethodIndex: 2 (API key) works properly when mobile filtered MethodIndex: 1 out!
	apiSess, err := mgr.StartSignIn(context.Background(), SignInStartRequest{
		ProviderID:  "workbuddy",
		MethodIndex: 2,
		APIKey:      "wb-api-secret",
	})
	if err != nil || apiSess.Status != "completed" {
		t.Fatalf("MethodIndex=2 API key sign-in failed: sess=%+v err=%v", apiSess, err)
	}
}

func TestHighSpeedTokenStreamBackpressure(t *testing.T) {
	// 1. Deterministic unit test verifying streamState credit batching (>= 32KB) and non-blocking enqueue
	rIn, wOut := io.Pipe()
	var creditFrames []map[string]any
	doneRead := make(chan struct{})
	go func() {
		defer close(doneRead)
		dec := json.NewDecoder(rIn)
		for {
			var frame map[string]any
			if err := dec.Decode(&frame); err != nil {
				return
			}
			creditFrames = append(creditFrames, frame)
		}
	}()

	bh := &BunHost{
		stdin:   wOut,
		pending: make(map[int64]*rpcPending),
	}
	ss := newStreamState(bh, 1)
	bh.pending[1] = &rpcPending{stream: ss}

	// Push 40 small 256-byte chunks synchronously (never blocks even with no reader yet!)
	chunkCount := 40
	var expected bytes.Buffer
	for i := 0; i < chunkCount; i++ {
		payload := bytes.Repeat([]byte{byte('a' + (i % 26))}, 256)
		expected.Write(payload)
		if err := ss.enqueue(payload); err != nil {
			t.Fatalf("enqueue failed: %v", err)
		}
	}

	// Read while upstream stream is still active so coalesced credits flush over RPC.
	got := make([]byte, expected.Len())
	if _, err := io.ReadFull(ss, got); err != nil {
		t.Fatalf("ReadFull failed: %v", err)
	}
	ss.finish()
	if tail, err := io.ReadAll(ss); err != nil || len(tail) != 0 {
		t.Fatalf("expected clean EOF after finish, got len=%d err=%v", len(tail), err)
	}
	if !bytes.Equal(got, expected.Bytes()) {
		t.Fatalf("stream payload mismatch: got %d want %d", len(got), expected.Len())
	}
	_ = wOut.Close()
	<-doneRead

	// 40 chunks * (256 + 2048) = 92,160 cost -> batched into 2 coalesced credits (>= 32KB) instead of 40!
	if len(creditFrames) >= 10 || len(creditFrames) < 1 {
		t.Fatalf("expected coalesced credit batches (<10 for 40 chunks), got %d frames", len(creditFrames))
	}

	// 2. Real BunHost concurrent backpressure test: slow stalled stream never blocks concurrent RPC/fast stream
	bun := DetectBun("")
	if bun == "" {
		return
	}

	streamServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		fl, _ := w.(http.Flusher)
		switch r.URL.Path {
		case "/v1/slow":
			// Exceed 512 KiB window across many chunks (700 KiB total)
			chunk := "data: " + strings.Repeat("x", 8192) + "\n\n"
			for i := 0; i < 88; i++ {
				_, _ = w.Write([]byte(chunk))
				if fl != nil {
					fl.Flush()
				}
			}
			_, _ = w.Write([]byte("data: [DONE]\n\n"))
		case "/v1/fast":
			_, _ = w.Write([]byte("data: fast-ok\n\ndata: [DONE]\n\n"))
		}
	}))
	defer streamServer.Close()

	dataDir := t.TempDir()
	pkgDir := PackageDir(dataDir, "bp-mock-plugin")
	_ = os.MkdirAll(pkgDir, 0o755)
	_ = os.WriteFile(filepath.Join(pkgDir, "package.json"), []byte(`{"name":"bp-mock-plugin","version":"1.0.0","main":"index.mjs"}`), 0o644)
	_ = os.WriteFile(filepath.Join(pkgDir, "index.mjs"), []byte(`
export default async () => ({
  config: async (cfg) => {
    cfg.provider = cfg.provider || {};
    cfg.provider["bp"] = {
      name: "BP",
      api: "`+streamServer.URL+`/v1",
      npm: "@ai-sdk/openai-compatible",
      models: { "m": { id: "m", name: "m", free: true } }
    };
  },
  auth: {
    provider: "bp",
    methods: [{ type: "api", label: "key", keyless: true, authorize: async () => ({ type: "success", key: "k" }) }],
    loader: async () => ({ baseURL: "`+streamServer.URL+`/v1", apiKey: "k" })
  }
});
`), 0o644)

	st, _ := store.Open(dataDir)
	_ = st.UpsertPluginEntry(types.InstalledPluginEntry{Package: "bp-mock-plugin", Spec: "bp-mock-plugin", Enabled: true})
	mgr := NewManager(st, bun, t.TempDir(), "", "", nil)
	defer mgr.Stop()
	if err := mgr.Reload(context.Background()); err != nil {
		t.Fatal(err)
	}

	// Open stream 1 (> 700KB), read only 32 bytes, pause WITHOUT draining
	slowResp, err := mgr.bunHost.Fetch(context.Background(), map[string]any{
		"provider": "bp", "model": "m", "npm": "@ai-sdk/openai-compatible",
		"url": streamServer.URL + "/v1/slow", "method": "POST",
	})
	if err != nil {
		t.Fatalf("slow Fetch failed: %v", err)
	}
	defer slowResp.Body.Close()
	headBuf := make([]byte, 32)
	if _, err := io.ReadFull(slowResp.Body, headBuf); err != nil {
		t.Fatalf("read head from slow stream: %v", err)
	}

	// While slow stream #1 is completely paused past its buffer, providers RPC and fast stream MUST finish quickly!
	fastCtx, cancelFast := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancelFast()
	if err := mgr.RefreshProviders(fastCtx); err != nil {
		t.Fatalf("concurrent RPC blocked by stalled stream: %v", err)
	}
	fastResp, err := mgr.bunHost.Fetch(fastCtx, map[string]any{
		"provider": "bp", "model": "m", "npm": "@ai-sdk/openai-compatible",
		"url": streamServer.URL + "/v1/fast", "method": "POST",
	})
	if err != nil {
		t.Fatalf("concurrent fast Fetch blocked: %v", err)
	}
	fastBody, _ := io.ReadAll(fastResp.Body)
	fastResp.Body.Close()
	if !strings.Contains(string(fastBody), "fast-ok") {
		t.Fatalf("unexpected fast stream body: %s", string(fastBody))
	}

	// Now drain rest of stalled 700KB stream #1 -> proves credit flow-control resumes cleanly without deadlock!
	restSlow, err := io.ReadAll(slowResp.Body)
	if err != nil {
		t.Fatalf("drain slow stream failed: %v", err)
	}
	totalSlow := 32 + len(restSlow)
	if totalSlow < 700*1024 || !strings.Contains(string(restSlow), "data: [DONE]") {
		t.Fatalf("expected full >700KB stream through backpressure window, got %d bytes", totalSlow)
	}
	t.Logf("verified concurrent stream non-blocking + full %d-byte backpressured stream", totalSlow)
	_ = fmt.Sprintf("")
}
