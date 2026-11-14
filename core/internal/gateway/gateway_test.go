package gateway

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/falcon-gateway/falcon/core/internal/plugin"
	"github.com/falcon-gateway/falcon/core/internal/router"
	"github.com/falcon-gateway/falcon/core/internal/store"
	"github.com/falcon-gateway/falcon/core/internal/types"
)

func freePort(t *testing.T) int {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := ln.Addr().(*net.TCPAddr).Port
	_ = ln.Close()
	return port
}

func TestGatewayEndToEndFailoverRedactAndRelisten(t *testing.T) {
	// Upstream 1: always returns 429 to trigger failover
	upFail := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusTooManyRequests)
		_, _ = w.Write([]byte(`{"error":"rate limited"}`))
	}))
	defer upFail.Close()

	// Upstream 2: OpenAI SSE server verifying pass-through prompt (no redaction)
	var seenPrompt string
	upOK := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		seenPrompt = string(body)
		w.Header().Set("Content-Type", "text/event-stream")
		_, _ = w.Write([]byte("data: {\"id\":\"c1\",\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"\"}}]}\n\n"))
		_, _ = w.Write([]byte("data: {\"id\":\"c1\",\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Echo ok!\"}}]}\n\n"))
		_, _ = w.Write([]byte("data: {\"id\":\"c1\",\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":15,\"completion_tokens\":6,\"total_tokens\":21}}\n\n"))
		_, _ = w.Write([]byte("data: [DONE]\n\n"))
	}))
	defer upOK.Close()

	st, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	port1 := freePort(t)
	redactOn := true
	_, _, err = st.UpdateSettings(types.SettingsPatch{
		Port:          &port1,
		RedactEnabled: &redactOn,
		RedactRestore: &redactOn,
	})
	if err != nil {
		t.Fatal(err)
	}
	_, _ = st.UpsertProvider(types.Provider{
		ID:       "p-fail",
		Name:     "FailProvider",
		Preset:   "openai",
		Protocol: types.ProtocolOpenAI,
		BaseURL:  upFail.URL + "/v1",
		Enabled:  true,
		Keys:     []types.ProviderKey{{ID: "k1", Secret: "sk-up-1", Enabled: true, Weight: 1}},
		Models:   []string{"gpt-4o"},
	})
	_, _ = st.UpsertProvider(types.Provider{
		ID:       "p-ok",
		Name:     "OkProvider",
		Preset:   "openai",
		Protocol: types.ProtocolOpenAI,
		BaseURL:  upOK.URL + "/v1",
		Enabled:  true,
		Keys:     []types.ProviderKey{{ID: "k2", Secret: "sk-up-2", Enabled: true, Weight: 1}},
		Models:   []string{"gpt-4o"},
	})
	_, _ = st.UpsertGroup(types.RoutingGroup{
		ID:       "g1",
		Name:     "smart",
		Strategy: types.StrategyOrder,
		Targets:  []string{"p-fail/gpt-4o", "p-ok/gpt-4o"},
		Enabled:  true,
	})

	pm := plugin.NewManager(st, "/nonexistent/bun", t.TempDir(), "", "", nil)
	gw := New(st, router.New(), pm, nil)
	if err := gw.Start(); err != nil {
		t.Fatalf("gw.Start: %v", err)
	}
	defer func() { _ = gw.Stop(context.Background()) }()

	// Call Anthropic /v1/messages streaming against OpenAI upstream through routing group "smart"!
	reqBody := `{"model":"smart","max_tokens":128,"stream":true,"messages":[{"role":"user","content":"My key is sk-secret1234567890abcdef1234"}]}`
	resp, err := http.Post(fmt.Sprintf("http://127.0.0.1:%d/v1/messages", port1), "application/json", strings.NewReader(reqBody))
	if err != nil {
		t.Fatalf("POST /v1/messages: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("expected 200, got %d", resp.StatusCode)
	}
	sseOut, _ := io.ReadAll(resp.Body)
	if !strings.Contains(seenPrompt, "sk-secret1234567890abcdef1234") {
		t.Fatalf("expected unmasked prompt when redaction removed, got: %s", seenPrompt)
	}
	if strings.Contains(seenPrompt, "[REDACTED_KEY_1]") {
		t.Fatalf("redaction should be disabled permanently: %s", seenPrompt)
	}
	if !strings.Contains(string(sseOut), "Echo ok!") {
		t.Fatalf("expected text in Anthropic SSE output, got:\n%s", string(sseOut))
	}
	if !strings.Contains(string(sseOut), "event: message_stop") {
		t.Fatalf("expected Anthropic SSE events, got:\n%s", string(sseOut))
	}

	// Verify request log was recorded with failover attempt and 0 redactions
	logs := st.GetLogs(10)
	if len(logs) != 1 || len(logs[0].Attempts) != 2 || logs[0].RedactedCount != 0 {
		t.Fatalf("unexpected request log: %+v", logs)
	}

	// Hot Relisten to a new port
	port2 := freePort(t)
	_, _, err = st.UpdateSettings(types.SettingsPatch{Port: &port2})
	if err != nil {
		t.Fatal(err)
	}
	if err := gw.Relisten(); err != nil {
		t.Fatalf("Relisten: %v", err)
	}
	healthResp, err := http.Get(fmt.Sprintf("http://127.0.0.1:%d/health", port2))
	if err != nil {
		t.Fatalf("GET /health on new port: %v", err)
	}
	defer healthResp.Body.Close()
	var h map[string]any
	_ = json.NewDecoder(healthResp.Body).Decode(&h)
	if h["ok"] != true {
		t.Fatalf("unexpected health response: %+v", h)
	}
	_ = time.Millisecond
}

func TestSelectedModelsSubsetRoutingAndListing(t *testing.T) {
	st, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	gwPort := freePort(t)
	allowKeyless := true
	_, _, err = st.UpdateSettings(types.SettingsPatch{
		Port:              &gwPort,
		AllowLocalKeyless: &allowKeyless,
	})
	if err != nil {
		t.Fatal(err)
	}

	up := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"id":"chatcmpl-1","object":"chat.completion","model":"m-active","choices":[{"index":0,"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}],"usage":{"prompt_tokens":2,"completion_tokens":1,"total_tokens":3}}`))
	}))
	defer up.Close()

	_, err = st.UpsertProvider(types.Provider{
		ID:             "selprov",
		Name:           "Subset Provider",
		Preset:         "custom",
		Protocol:       types.ProtocolOpenAI,
		BaseURL:        up.URL + "/v1",
		Enabled:        true,
		Keys:           []types.ProviderKey{{ID: "k1", Secret: "sk-up", Enabled: true, Weight: 1}},
		Models:         []string{"m-active", "m-unchecked"},
		SelectedModels: []string{"m-active"},
	})
	if err != nil {
		t.Fatal(err)
	}

	gw := New(st, router.New(), nil, nil)
	if err := gw.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() { _ = gw.Stop(context.Background()) }()

	gwBase := fmt.Sprintf("http://127.0.0.1:%d", gwPort)

	// 1. Status().ModelCount should only count SelectedModels (1)
	if got := gw.Status().ModelCount; got != 1 {
		t.Fatalf("expected ModelCount=1, got %d", got)
	}

	// 2. /v1/models should expose selprov/m-active and NOT selprov/m-unchecked
	resp, err := http.Get(gwBase + "/v1/models")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var modList struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	_ = json.NewDecoder(resp.Body).Decode(&modList)
	if len(modList.Data) != 1 || modList.Data[0].ID != "selprov/m-active" {
		t.Fatalf("expected only selprov/m-active in /v1/models, got %+v", modList.Data)
	}

	// 2b. /api/tags should also expose only selprov/m-active
	tagsResp, err := http.Get(gwBase + "/api/tags")
	if err != nil {
		t.Fatal(err)
	}
	defer tagsResp.Body.Close()
	var tagsList struct {
		Models []struct {
			Name string `json:"name"`
		} `json:"models"`
	}
	_ = json.NewDecoder(tagsResp.Body).Decode(&tagsList)
	if len(tagsList.Models) != 1 || tagsList.Models[0].Name != "selprov/m-active" {
		t.Fatalf("expected only selprov/m-active in /api/tags, got %+v", tagsList.Models)
	}

	// 3. Bare unchecked model should not route (404)
	reqUnchecked := `{"model":"m-unchecked","messages":[{"role":"user","content":"hi"}]}`
	unResp, err := http.Post(gwBase+"/v1/chat/completions", "application/json", strings.NewReader(reqUnchecked))
	if err != nil {
		t.Fatal(err)
	}
	unResp.Body.Close()
	if unResp.StatusCode != http.StatusNotFound {
		t.Fatalf("expected 404 for unchecked model, got %d", unResp.StatusCode)
	}

	// 4. Bare active model routes cleanly (200)
	reqActive := `{"model":"m-active","messages":[{"role":"user","content":"hi"}]}`
	actResp, err := http.Post(gwBase+"/v1/chat/completions", "application/json", strings.NewReader(reqActive))
	if err != nil {
		t.Fatal(err)
	}
	actResp.Body.Close()
	if actResp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 for selected model, got %d", actResp.StatusCode)
	}

	// 5. Explicitly empty SelectedModels ([]string{}) persists and exposes 0 models
	_, err = st.UpsertProvider(types.Provider{
		ID:             "selprov",
		Name:           "Subset Provider",
		Preset:         "custom",
		Protocol:       types.ProtocolOpenAI,
		BaseURL:        up.URL + "/v1",
		Enabled:        true,
		Keys:           []types.ProviderKey{{ID: "k1", Secret: "sk-up", Enabled: true, Weight: 1}},
		Models:         []string{"m-active", "m-unchecked"},
		SelectedModels: []string{},
	})
	if err != nil {
		t.Fatal(err)
	}
	if got := gw.Status().ModelCount; got != 0 {
		t.Fatalf("expected ModelCount=0 when SelectedModels is empty, got %d", got)
	}
}

func TestGatewayRelistenLoopbackLAN(t *testing.T) {
	st, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	port := freePort(t)
	lanFalse := false
	_, _, err = st.UpdateSettings(types.SettingsPatch{
		Port:       &port,
		LanEnabled: &lanFalse,
	})
	if err != nil {
		t.Fatal(err)
	}

	gw := New(st, router.New(), nil, nil)
	if err := gw.Start(); err != nil {
		t.Fatalf("gw.Start: %v", err)
	}
	defer func() { _ = gw.Stop(context.Background()) }()

	checkHealth := func(url string) {
		t.Helper()
		resp, err := http.Get(url + "/health")
		if err != nil {
			t.Fatalf("GET %s/health: %v", url, err)
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("expected 200 from %s/health, got %d", url, resp.StatusCode)
		}
	}

	if got := gw.Status().ListenAddr; got != fmt.Sprintf("127.0.0.1:%d", port) {
		t.Fatalf("expected 127.0.0.1:%d, got %s", port, got)
	}
	checkHealth(fmt.Sprintf("http://127.0.0.1:%d", port))

	// Switch 127.0.0.1:P -> 0.0.0.0:P on the exact same port
	lanTrue := true
	_, _, err = st.UpdateSettings(types.SettingsPatch{LanEnabled: &lanTrue})
	if err != nil {
		t.Fatal(err)
	}
	if err := gw.Relisten(); err != nil {
		t.Fatalf("Relisten to LAN on same port %d failed: %v", port, err)
	}
	stLAN := gw.Status()
	if (stLAN.ListenAddr != fmt.Sprintf("0.0.0.0:%d", port) && stLAN.ListenAddr != fmt.Sprintf("[::]:%d", port)) || !stLAN.Running || !stLAN.LanEnabled {
		t.Fatalf("unexpected status after LAN relisten: %+v", stLAN)
	}
	checkHealth(fmt.Sprintf("http://127.0.0.1:%d", port))
	if len(stLAN.LanUrls) > 0 {
		anyLanOK := false
		for _, lanURL := range stLAN.LanUrls {
			if r, err := http.Get(lanURL + "/health"); err == nil {
				r.Body.Close()
				if r.StatusCode == http.StatusOK {
					anyLanOK = true
					break
				}
			}
		}
		if !anyLanOK {
			t.Fatalf("expected at least one LAN URL %v to respond /health", stLAN.LanUrls)
		}
	}

	// Switch back 0.0.0.0:P -> 127.0.0.1:P on the exact same port
	_, _, err = st.UpdateSettings(types.SettingsPatch{LanEnabled: &lanFalse})
	if err != nil {
		t.Fatal(err)
	}
	if err := gw.Relisten(); err != nil {
		t.Fatalf("Relisten back to loopback on same port %d failed: %v", port, err)
	}
	stLoop := gw.Status()
	if stLoop.ListenAddr != fmt.Sprintf("127.0.0.1:%d", port) || !stLoop.Running || stLoop.LanEnabled {
		t.Fatalf("unexpected status after loopback relisten: %+v", stLoop)
	}
	checkHealth(fmt.Sprintf("http://127.0.0.1:%d", port))
}

func TestFilterAndSortLANIPs(t *testing.T) {
	entries := []ifaceIP{
		{name: "utun4", ip: net.ParseIP("198.18.0.1")},
		{name: "utun5", ip: net.ParseIP("198.19.1.2")},
		{name: "rmnet_data0", ip: net.ParseIP("10.123.45.6")},
		{name: "CCMNI0", ip: net.ParseIP("100.64.0.1")},
		{name: "pdp_ip0", ip: net.ParseIP("10.0.0.2")},
		{name: "clat4", ip: net.ParseIP("192.0.0.4")},
		{name: "dummy0", ip: net.ParseIP("172.16.0.5")},
		{name: "utun3", ip: net.ParseIP("100.79.234.90")},
		{name: "wlan0", ip: net.ParseIP("192.168.1.73")},
		{name: "eth0", ip: net.ParseIP("10.0.0.12")},
		{name: "lo", ip: net.ParseIP("127.0.0.1")},
	}
	got := filterAndSortLANIPs(entries)
	want := []string{"10.0.0.12", "192.168.1.73", "100.79.234.90"}
	if len(got) != len(want) {
		t.Fatalf("expected %v, got %v", want, got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("index %d: expected %v, got %v", i, want, got)
		}
	}
}

func TestGatewayWorkBuddyV2NonStreamingFoldAndPluginSelectedModels(t *testing.T) {
	bun := plugin.DetectBun("")
	if bun == "" {
		t.Fatal("bun binary not found in PATH or bundled location; required for gateway plugin integration test")
	}

	var sawPath string
	var sawUpstreamStream bool
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		sawPath = r.URL.Path
		bodyBytes, _ := io.ReadAll(r.Body)
		var reqObj map[string]any
		_ = json.Unmarshal(bodyBytes, &reqObj)
		if v, ok := reqObj["stream"].(bool); ok {
			sawUpstreamStream = v
		}
		if !sawUpstreamStream {
			http.Error(w, "stream-only endpoint", http.StatusBadRequest)
			return
		}
		w.Header().Set("Content-Type", "text/event-stream")
		w.WriteHeader(http.StatusOK)
		_, _ = fmt.Fprint(w,
			"data: {\"id\":\"wb-1\",\"model\":\"glm-5.3\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"WorkBuddy \"}}]}\n\n"+
				"data: {\"id\":\"wb-1\",\"model\":\"glm-5.3\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"v2 answer\"}}]}\n\n"+
				"data: {\"id\":\"wb-1\",\"model\":\"glm-5.3\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":7,\"completion_tokens\":3,\"total_tokens\":10}}\n\n"+
				"data: [DONE]\n\n",
		)
	}))
	defer upstream.Close()

	dataDir := t.TempDir()
	cacheDir := t.TempDir()
	pkg := "@magpie-community/opencode-workbuddy-auth"
	pkgDir := filepath.Join(dataDir, "plugins", "node_modules", pkg)
	if err := os.MkdirAll(pkgDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(pkgDir, "package.json"), []byte(`{"name":"@magpie-community/opencode-workbuddy-auth","version":"1.0.0","main":"index.mjs"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	pluginJS := fmt.Sprintf(`
export async function WorkBuddyAuthPlugin() {
  return {
    auth: {
      provider: "workbuddy",
      loader: async () => ({
        apiKey: "wb-test-key",
        baseURL: %q,
        async fetch(input, init) {
          return globalThis.fetch(input, init);
        },
      }),
      methods: [{ type: "api", label: "WorkBuddy Key" }],
    },
    async config(cfg) {
      cfg.provider = cfg.provider || {};
      cfg.provider.workbuddy = {
        id: "workbuddy",
        name: "WorkBuddy (CN)",
        api: %q,
        models: {
          "glm-5.3": { id: "glm-5.3", name: "GLM 5.3", api: { id: "glm-5.3", npm: "@ai-sdk/openai-compatible", url: %q } },
          "deepseek-v4": { id: "deepseek-v4", name: "DeepSeek V4", api: { id: "deepseek-v4", npm: "@ai-sdk/openai-compatible", url: %q } }
        }
      };
    }
  };
}
`, upstream.URL+"/v2", upstream.URL+"/v2", upstream.URL+"/v2", upstream.URL+"/v2")
	if err := os.WriteFile(filepath.Join(pkgDir, "index.mjs"), []byte(pluginJS), 0o644); err != nil {
		t.Fatal(err)
	}
	authFile := filepath.Join(dataDir, "plugin-auth.json")
	if err := os.WriteFile(authFile, []byte(`{"workbuddy":{"type":"api","key":"wb-test-key"}}`), 0o600); err != nil {
		t.Fatal(err)
	}

	st, err := store.Open(dataDir)
	if err != nil {
		t.Fatal(err)
	}
	if err := st.UpsertPluginEntry(types.InstalledPluginEntry{
		Package: pkg,
		Spec:    pkg,
		Enabled: true,
	}); err != nil {
		t.Fatal(err)
	}
	port := freePort(t)
	if _, _, err := st.UpdateSettings(types.SettingsPatch{Port: &port}); err != nil {
		t.Fatal(err)
	}

	pm := plugin.NewManager(st, bun, cacheDir, "", "", nil)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	if err := pm.Reload(ctx); err != nil {
		t.Fatalf("pm.Reload: %v", err)
	}
	defer pm.Stop()

	if err := pm.SetSelectedModels(pkg, "workbuddy", []string{"glm-5.3"}); err != nil {
		t.Fatalf("SetSelectedModels: %v", err)
	}

	gw := New(st, router.New(), pm, nil)
	if err := gw.Start(); err != nil {
		t.Fatalf("gw.Start: %v", err)
	}
	defer func() {
		shutCtx, shutCancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer shutCancel()
		_ = gw.Stop(shutCtx)
	}()

	baseURL := fmt.Sprintf("http://127.0.0.1:%d", port)

	// 1. /v1/models reflects only selected workbuddy/glm-5.3
	modelsResp, err := http.Get(baseURL + "/v1/models")
	if err != nil {
		t.Fatalf("GET /v1/models: %v", err)
	}
	modelsBody, _ := io.ReadAll(modelsResp.Body)
	modelsResp.Body.Close()
	if modelsResp.StatusCode != http.StatusOK {
		t.Fatalf("GET /v1/models status %d: %s", modelsResp.StatusCode, string(modelsBody))
	}
	modelsText := string(modelsBody)
	if !strings.Contains(modelsText, `"workbuddy/glm-5.3"`) || strings.Contains(modelsText, `"workbuddy/deepseek-v4"`) {
		t.Fatalf("unexpected /v1/models output with SelectedModels filter: %s", modelsText)
	}

	// 2. Deselected model returns 404
	disallowedReq, _ := http.NewRequest(http.MethodPost, baseURL+"/v1/chat/completions", strings.NewReader(`{"model":"workbuddy/deepseek-v4","stream":false,"messages":[{"role":"user","content":"hi"}]}`))
	disallowedReq.Header.Set("Content-Type", "application/json")
	disallowedResp, err := http.DefaultClient.Do(disallowedReq)
	if err != nil {
		t.Fatalf("POST deselected model: %v", err)
	}
	disallowedResp.Body.Close()
	if disallowedResp.StatusCode != http.StatusNotFound {
		t.Fatalf("expected 404 for deselected workbuddy/deepseek-v4, got %d", disallowedResp.StatusCode)
	}

	// 3. Non-streaming client request against /v2 WorkBuddy stream-only upstream folds SSE cleanly to JSON
	chatReq, _ := http.NewRequest(http.MethodPost, baseURL+"/v1/chat/completions", strings.NewReader(`{"model":"workbuddy/glm-5.3","stream":false,"messages":[{"role":"user","content":"hello"}]}`))
	chatReq.Header.Set("Content-Type", "application/json")
	chatResp, err := http.DefaultClient.Do(chatReq)
	if err != nil {
		t.Fatalf("POST /v1/chat/completions: %v", err)
	}
	chatBody, _ := io.ReadAll(chatResp.Body)
	chatResp.Body.Close()
	if chatResp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 from WorkBuddy /v2 folded request, got %d: %s", chatResp.StatusCode, string(chatBody))
	}
	if sawPath != "/v2/chat/completions" {
		t.Fatalf("expected upstream path /v2/chat/completions, got %q", sawPath)
	}
	if !sawUpstreamStream {
		t.Fatalf("expected upstream /v2 request to force stream:true")
	}
	var parsed map[string]any
	if err := json.Unmarshal(chatBody, &parsed); err != nil {
		t.Fatalf("expected JSON body from folded SSE, got %v: %s", err, string(chatBody))
	}
	choices, _ := parsed["choices"].([]any)
	if len(choices) != 1 {
		t.Fatalf("expected 1 choice, got %s", string(chatBody))
	}
	msg, _ := choices[0].(map[string]any)["message"].(map[string]any)
	if msg["content"] != "WorkBuddy v2 answer" {
		t.Fatalf("expected folded assistant content %q, got %#v (full=%s)", "WorkBuddy v2 answer", msg["content"], string(chatBody))
	}
	usageMap, _ := parsed["usage"].(map[string]any)
	if usageMap["prompt_tokens"] != float64(7) || usageMap["completion_tokens"] != float64(3) || usageMap["total_tokens"] != float64(10) {
		t.Fatalf("expected folded usage 7/3/10, got %#v", usageMap)
	}
}
