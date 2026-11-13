package provider

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/falcon-gateway/falcon/core/internal/types"
)

func TestPresetsAndKeySelection(t *testing.T) {
	if len(Presets()) < 15 {
		t.Fatalf("expected at least 15 presets, got %d", len(Presets()))
	}
	p := types.Provider{
		ID:       "p1",
		Protocol: types.ProtocolOpenAI,
		Keys: []types.ProviderKey{
			{ID: "k1", Secret: "sk-1", Enabled: false, Weight: 10},
			{ID: "k2", Secret: "sk-2", Enabled: true, Weight: 1},
			{ID: "k3", Secret: "sk-3", Enabled: true, Weight: 1},
		},
	}
	picked, ok := PickKey(p, map[string]bool{"k2": true})
	if !ok || picked.ID != "k3" {
		t.Fatalf("expected k3 when k2 skipped and k1 disabled, got %+v ok=%v", picked, ok)
	}
}

func TestFetchModelsAndConnectivityProbe(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/models":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"data":[{"id":"gpt-4o"},{"id":"gpt-4o-mini"}]}`))
		case "/v1/chat/completions":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"id":"1","model":"gpt-4o","choices":[{"index":0,"message":{"role":"assistant","content":"OK"},"finish_reason":"stop"}],"usage":{"prompt_tokens":3,"completion_tokens":1,"total_tokens":4}}`))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer srv.Close()

	p := types.Provider{
		ID:       "test",
		Preset:   "openai",
		Protocol: types.ProtocolOpenAI,
		BaseURL:  srv.URL + "/v1",
		Enabled:  true,
		Keys:     []types.ProviderKey{{ID: "k1", Secret: "sk-test", Enabled: true, Weight: 1}},
	}

	models, err := FetchModels(context.Background(), srv.Client(), p)
	if err != nil || len(models) != 2 {
		t.Fatalf("FetchModels failed: models=%v err=%v", models, err)
	}
	p.Models = models

	res := TestConnectivity(context.Background(), srv.Client(), p, "")
	if !res.Ok || res.StatusCode != 200 || res.ReplyPreview != "OK" {
		t.Fatalf("TestConnectivity failed: %+v", res)
	}
}
