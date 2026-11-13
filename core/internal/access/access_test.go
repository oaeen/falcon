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

	// 7. Loopback keyless disabled -> 401
	settings.AllowLocalKeyless = false
	_, code, _ = Authenticate(req, st, settings)
	if code != http.StatusUnauthorized {
		t.Fatalf("expected 401 when allowLocalKeyless=false, got %d", code)
	}
}
