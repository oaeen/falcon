package plugin

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha512"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

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
		"opencode-cursor-auth",
		"opencode-windsurf-auth",
		"opencode-trae-auth",
		"opencode-workbuddy-auth",
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
