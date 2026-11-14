package access

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/falcon-gateway/falcon/core/internal/store"
	"github.com/falcon-gateway/falcon/core/internal/types"
)

func TestAuthenticateLoopbackVsLAN(t *testing.T) {
	st, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	k, _, err := st.CreateOrUpdateKey(types.AccessKey{
		Name:           "LAN Key",
		Enabled:        true,
		AllowedModels:  []string{"openai/*"},
		DailyLimitReqs: 2,
	})
	if err != nil {
		t.Fatal(err)
	}

	settings := st.Settings()
	reqAccess := true
	settings.RequireAccessKey = reqAccess

	// 1. Loopback without key succeeds when allowLocalKeyless=true
	req := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", nil)
	req.RemoteAddr = "127.0.0.1:54321"
	id, code, _ := Authenticate(req, st, settings)
	if code != 0 || !id.Keyless || id.Peer.Kind != "loopback" {
		t.Fatalf("expected loopback keyless pass, got code=%d id=%+v", code, id)
	}

	// 2. Loopback with X-Forwarded-For LAN IP is treated as LAN -> 401
	reqXFF := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", nil)
	reqXFF.RemoteAddr = "127.0.0.1:54321"
	reqXFF.Header.Set("X-Forwarded-For", "192.168.1.42")
	_, code, _ = Authenticate(reqXFF, st, settings)
	if code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for XFF LAN peer without key, got %d", code)
	}

	// 3. LAN peer without key -> 401
	reqLAN := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", nil)
	reqLAN.RemoteAddr = "192.168.1.50:12345"
	_, code, _ = Authenticate(reqLAN, st, settings)
	if code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for LAN without key, got %d", code)
	}

	// 4. LAN peer with valid Bearer key -> pass + model scope check
	reqLAN.Header.Set("Authorization", "Bearer "+k.Secret)
	id, code, _ = Authenticate(reqLAN, st, settings)
	if code != 0 || id.KeyID != k.ID {
		t.Fatalf("expected auth pass, got code=%d", code)
	}
	if !ModelAllowed(id, "openai/gpt-4o") {
		t.Fatal("expected openai/gpt-4o allowed")
	}
	if ModelAllowed(id, "anthropic/claude-sonnet-4") {
		t.Fatal("expected anthropic/claude-sonnet-4 disallowed")
	}

	// 5. CIDR allowlist blocks non-matching LAN IP
	settings.AllowIps = []string{"192.168.2.0/24"}
	_, code, _ = Authenticate(reqLAN, st, settings)
	if code != http.StatusForbidden {
		t.Fatalf("expected 403 for IP outside allowlist, got %d", code)
	}
	settings.AllowIps = []string{"192.168.1.0/24"}
	_, code, _ = Authenticate(reqLAN, st, settings)
	if code != 0 {
		t.Fatalf("expected 0 for IP inside allowlist, got %d", code)
	}

	// 6. Daily request limit enforced
	st.RecordRequest(types.RequestLogEntry{KeyID: k.ID, StatusCode: 200}, nil)
	st.RecordRequest(types.RequestLogEntry{KeyID: k.ID, StatusCode: 200}, nil)
	_, code, _ = Authenticate(reqLAN, st, settings)
	if code != http.StatusTooManyRequests {
		t.Fatalf("expected 429 after 2 requests, got %d", code)
	}

	// 7. Loopback keyless disabled -> 401 when requireAccessKey=true
	settings.AllowLocalKeyless = false
	_, code, _ = Authenticate(req, st, settings)
	if code != http.StatusUnauthorized {
		t.Fatalf("expected 401 when allowLocalKeyless=false, got %d", code)
	}
}

func TestOptionalAccessKeyAndLanDefaults(t *testing.T) {
	st, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	settings := st.Settings()
	if settings.Port != 18787 || settings.LanEnabled || settings.RequireAccessKey || !settings.AllowLocalKeyless || settings.RedactEnabled {
		t.Fatalf("unexpected default settings: %+v", settings)
	}

	// Verify RedactEnabled cannot be re-enabled through UpdateSettings.
	wantTrue := true
	updated, _, err := st.UpdateSettings(types.SettingsPatch{RedactEnabled: &wantTrue})
	if err != nil {
		t.Fatal(err)
	}
	if updated.RedactEnabled {
		t.Fatalf("expected RedactEnabled forced false, got true")
	}

	k, _, err := st.CreateOrUpdateKey(types.AccessKey{
		Name:          "Scoped LAN Key",
		Enabled:       true,
		AllowedModels: []string{"openai/*"},
	})
	if err != nil {
		t.Fatal(err)
	}

	// Loopback keyless passes by default
	reqLoop := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", nil)
	reqLoop.RemoteAddr = "127.0.0.1:41000"
	id, code, _ := Authenticate(reqLoop, st, st.Settings())
	if code != 0 || !id.Keyless {
		t.Fatalf("expected loopback pass without key, got code=%d id=%+v", code, id)
	}

	// LAN keyless passes when requireAccessKey=false
	reqLAN := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", nil)
	reqLAN.RemoteAddr = "192.168.1.99:41000"
	id, code, _ = Authenticate(reqLAN, st, st.Settings())
	if code != 0 || !id.Keyless || id.Peer.Kind != "lan" || id.Peer.IP != "192.168.1.99" {
		t.Fatalf("expected LAN keyless pass when requireAccessKey=false, got code=%d id=%+v", code, id)
	}

	// Dummy bearer header from client apps also succeeds cleanly when requireAccessKey=false
	reqDummy := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", nil)
	reqDummy.RemoteAddr = "192.168.1.99:41000"
	reqDummy.Header.Set("Authorization", "Bearer dummy-app-token")
	id, code, _ = Authenticate(reqDummy, st, st.Settings())
	if code != 0 || !id.Keyless {
		t.Fatalf("expected dummy key to pass keyless when requireAccessKey=false, got code=%d", code)
	}

	// Valid managed key still binds identity and model allowlist
	reqKeyed := httptest.NewRequest(http.MethodPost, "/v1/chat/completions", nil)
	reqKeyed.RemoteAddr = "192.168.1.99:41000"
	reqKeyed.Header.Set("Authorization", "Bearer "+k.Secret)
	id, code, _ = Authenticate(reqKeyed, st, st.Settings())
	if code != 0 || id.KeyID != k.ID {
		t.Fatalf("expected valid key binding, got code=%d id=%+v", code, id)
	}
	if ModelAllowed(id, "anthropic/claude-sonnet-4") {
		t.Fatal("expected keyed model restriction to remain active")
	}

	// IP allowlist still protects LAN even when requireAccessKey=false
	patchIps := []string{"10.0.0.0/8"}
	_, _, err = st.UpdateSettings(types.SettingsPatch{AllowIps: &patchIps})
	if err != nil {
		t.Fatal(err)
	}
	_, code, _ = Authenticate(reqLAN, st, st.Settings())
	if code != http.StatusForbidden {
		t.Fatalf("expected 403 for LAN IP outside allowlist, got %d", code)
	}

	// Toggling requireAccessKey=true restores strict key enforcement on LAN
	_, _, err = st.UpdateSettings(types.SettingsPatch{AllowIps: &[]string{}, RequireAccessKey: &wantTrue})
	if err != nil {
		t.Fatal(err)
	}
	_, code, _ = Authenticate(reqLAN, st, st.Settings())
	if code != http.StatusUnauthorized {
		t.Fatalf("expected 401 when requireAccessKey=true on LAN, got %d", code)
	}
}

func TestApplyCORSDefaultAndRestricted(t *testing.T) {
	// Default (empty CorsOrigins) permits WebView / local web client Origins and reflects custom SDK headers.
	preReq := httptest.NewRequest(http.MethodOptions, "/v1/models", nil)
	preReq.Header.Set("Origin", "http://localhost")
	preReq.Header.Set("Access-Control-Request-Headers", "Authorization, x-stainless-os, Content-Type")
	preRec := httptest.NewRecorder()
	if handled := ApplyCORS(preRec, preReq, nil); !handled {
		t.Fatal("expected OPTIONS preflight to return handled=true")
	}
	if preRec.Code != http.StatusNoContent {
		t.Fatalf("expected 204 preflight, got %d", preRec.Code)
	}
	if got := preRec.Header().Get("Access-Control-Allow-Origin"); got != "*" {
		t.Fatalf("expected wildcard ACAO for empty CorsOrigins, got %q", got)
	}
	if got := preRec.Header().Get("Access-Control-Allow-Headers"); got != "Authorization, x-stainless-os, Content-Type" {
		t.Fatalf("expected reflected ACAH, got %q", got)
	}

	// Non-empty CorsOrigins enforces the allowlist strictly.
	restrictReq := httptest.NewRequest(http.MethodGet, "/v1/models", nil)
	restrictReq.Header.Set("Origin", "https://evil.example")
	restrictRec := httptest.NewRecorder()
	if handled := ApplyCORS(restrictRec, restrictReq, []string{"https://app.example"}); handled {
		t.Fatal("expected GET not to be treated as preflight")
	}
	if got := restrictRec.Header().Get("Access-Control-Allow-Origin"); got != "" {
		t.Fatalf("expected disallowed origin to have no ACAO, got %q", got)
	}

	okReq := httptest.NewRequest(http.MethodGet, "/v1/models", nil)
	okReq.Header.Set("Origin", "https://app.example")
	okRec := httptest.NewRecorder()
	ApplyCORS(okRec, okReq, []string{"https://app.example"})
	if got := okRec.Header().Get("Access-Control-Allow-Origin"); got != "https://app.example" {
		t.Fatalf("expected matched origin ACAO, got %q", got)
	}
}
