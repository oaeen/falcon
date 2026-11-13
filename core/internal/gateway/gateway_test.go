package gateway

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
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

	// Upstream 2: OpenAI SSE server verifying redaction + returning placeholder
	var seenPrompt string
	upOK := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		seenPrompt = string(body)
		w.Header().Set("Content-Type", "text/event-stream")
		_, _ = w.Write([]byte("data: {\"id\":\"c1\",\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"\"}}]}\n\n"))
		_, _ = w.Write([]byte("data: {\"id\":\"c1\",\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Echo [RED\"}}]}\n\n"))
		_, _ = w.Write([]byte("data: {\"id\":\"c1\",\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"ACTED_KEY_1]!\"}}]}\n\n"))
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
	if strings.Contains(seenPrompt, "sk-secret1234567890abcdef1234") {
		t.Fatalf("secret leaked to upstream: %s", seenPrompt)
	}
	if !strings.Contains(seenPrompt, "[REDACTED_KEY_1]") {
		t.Fatalf("expected redacted placeholder in upstream request: %s", seenPrompt)
	}
	if !strings.Contains(string(sseOut), "sk-secret1234567890abcdef1234") {
		t.Fatalf("expected restored secret in Anthropic SSE output, got:\n%s", string(sseOut))
	}
	if !strings.Contains(string(sseOut), "event: message_stop") {
		t.Fatalf("expected Anthropic SSE events, got:\n%s", string(sseOut))
	}

	// Verify request log was recorded with failover attempt
	logs := st.GetLogs(10)
	if len(logs) != 1 || len(logs[0].Attempts) != 2 || logs[0].RedactedCount != 1 {
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
