package engine

import (
	"context"
	"encoding/json"
	"net"
	"net/http"
	"testing"
)

func freePort(t *testing.T) int {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	p := ln.Addr().(*net.TCPAddr).Port
	_ = ln.Close()
	return p
}

func TestEngineStartStopAndStatus(t *testing.T) {
	gwPort := freePort(t)
	cfg := Config{
		DataDir:     t.TempDir(),
		CacheDir:    t.TempDir(),
		GatewayPort: gwPort,
		AdminAddr:   "127.0.0.1:0",
		AdminToken:  "tok-123",
		BunPath:     "/nonexistent/bun",
	}
	eng, err := StartInstance(context.Background(), cfg)
	if err != nil {
		t.Fatalf("StartInstance: %v", err)
	}
	defer func() { _ = eng.Stop(context.Background()) }()

	st := eng.Status()
	if !st.Running || st.Port != gwPort || st.PluginRuntimeMode != "embedded" {
		t.Fatalf("unexpected engine status: %+v", st)
	}

	req, _ := http.NewRequest(http.MethodGet, "http://"+eng.AdminAddr()+"/admin/v1/state", nil)
	req.Header.Set("Authorization", "Bearer tok-123")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("GET admin state: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("expected 200 from admin state, got %d", resp.StatusCode)
	}
	var payload map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&payload)
	statusObj := payload["status"].(map[string]any)
	if statusObj["pluginRuntimeMode"] != "embedded" {
		t.Fatalf("expected pluginRuntimeMode=embedded, got %v", statusObj["pluginRuntimeMode"])
	}
}
