package admin

import (
	"bytes"
	"context"
	"encoding/json"
	"net"
	"net/http"
	"testing"

	"github.com/falcon-gateway/falcon/core/internal/gateway"
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
	p := ln.Addr().(*net.TCPAddr).Port
	_ = ln.Close()
	return p
}

func TestAdminAPIAuthAndCRUD(t *testing.T) {
	st, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	gwPort := freePort(t)
	_, _, _ = st.UpdateSettings(types.SettingsPatch{
		Port: &gwPort,
	})

	pm := plugin.NewManager(st, "/nonexistent/bun", t.TempDir(), "", "", nil)
	gw := gateway.New(st, router.New(), pm, nil)
	// Use random port 0 for test
	adm := New(st, gw, pm, "127.0.0.1:0", "secret-token-123", nil)
	if err := adm.Start(); err != nil {
		t.Fatalf("adm.Start: %v", err)
	}
	defer func() { _ = adm.Stop(context.Background()) }()

	// Refuses non-loopback bind
	badAdm := New(st, gw, pm, "0.0.0.0:18788", "t", nil)
	if err := badAdm.Start(); err == nil {
		t.Fatal("expected error binding admin to 0.0.0.0")
	}

	baseURL := "http://" + adm.Addr()

	// Unauthenticated -> 401
	resp, err := http.Get(baseURL + "/admin/v1/state")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", resp.StatusCode)
	}

	// Authenticated state
	req, _ := http.NewRequest(http.MethodGet, baseURL+"/admin/v1/state", nil)
	req.Header.Set("Authorization", "Bearer secret-token-123")
	resp, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var state map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&state); err != nil {
		t.Fatal(err)
	}
	if _, ok := state["status"].(map[string]any); !ok {
		t.Fatalf("missing status in /admin/v1/state: %+v", state)
	}

	// Redact preview
	prevReq, _ := http.NewRequest(http.MethodPost, baseURL+"/admin/v1/redact/preview", bytes.NewBufferString(`{"text":"my key is sk-1234567890abcdef1234"}`))
	prevReq.Header.Set("Authorization", "Bearer secret-token-123")
	prevReq.Header.Set("Content-Type", "application/json")
	prevResp, err := http.DefaultClient.Do(prevReq)
	if err != nil {
		t.Fatal(err)
	}
	defer prevResp.Body.Close()
	var prevOut map[string]any
	_ = json.NewDecoder(prevResp.Body).Decode(&prevOut)
	if prevOut["totalHits"].(float64) != 1 {
		t.Fatalf("expected 1 redact hit, got %+v", prevOut)
	}

	// POST /admin/v1/settings toggling lanEnabled true <-> false on same gateway port
	if err := gw.Start(); err != nil {
		t.Fatalf("gw.Start: %v", err)
	}
	defer func() { _ = gw.Stop(context.Background()) }()

	setLAN := func(enabled bool) map[string]any {
		t.Helper()
		b, _ := json.Marshal(map[string]any{"lanEnabled": enabled})
		r, _ := http.NewRequest(http.MethodPost, baseURL+"/admin/v1/settings", bytes.NewReader(b))
		r.Header.Set("Authorization", "Bearer secret-token-123")
		r.Header.Set("Content-Type", "application/json")
		resp, err := http.DefaultClient.Do(r)
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("POST /admin/v1/settings lanEnabled=%v got %d", enabled, resp.StatusCode)
		}
		var out map[string]any
		_ = json.NewDecoder(resp.Body).Decode(&out)
		return out
	}

	lanRes := setLAN(true)
	if stObj := lanRes["status"].(map[string]any); stObj["lanEnabled"] != true {
		t.Fatalf("expected lanEnabled=true, got %+v", stObj)
	}
	loopRes := setLAN(false)
	if stObj := loopRes["status"].(map[string]any); stObj["lanEnabled"] != false {
		t.Fatalf("expected lanEnabled=false, got %+v", stObj)
	}
}
