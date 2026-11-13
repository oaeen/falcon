package access

import (
	"crypto/subtle"
	"encoding/json"
	"net"
	"net/http"
	"net/netip"
	"strings"

	"github.com/falcon-gateway/falcon/core/internal/store"
	"github.com/falcon-gateway/falcon/core/internal/types"
)

// PeerInfo describes the resolved client peer.
type PeerInfo struct {
	IP         string
	IsLoopback bool
	Kind       string // "loopback" | "lan"
}

// Identity describes the authenticated gateway caller.
type Identity struct {
	Peer     PeerInfo
	Key      *types.AccessKey
	Keyless  bool
	KeyID    string
	KeyName  string
}

// ResolvePeer determines the effective peer IP and whether the caller is truly loopback.
// A request is loopback only when its TCP remote address is loopback and any X-Forwarded-For
// hop is also loopback (preventing LAN spoofing via XFF).
func ResolvePeer(r *http.Request) PeerInfo {
	remoteHost := hostOnly(r.RemoteAddr)
	remoteAddr, remoteOK := parseIP(remoteHost)
	remoteLoopback := remoteOK && remoteAddr.IsLoopback()

	effectiveIP := remoteHost
	if remoteLoopback {
		if xff := strings.TrimSpace(r.Header.Get("X-Forwarded-For")); xff != "" {
			first := strings.TrimSpace(strings.Split(xff, ",")[0])
			if addr, ok := parseIP(hostOnly(first)); ok {
				effectiveIP = addr.String()
				if !addr.IsLoopback() {
					return PeerInfo{IP: effectiveIP, IsLoopback: false, Kind: "lan"}
				}
			}
		} else if xri := strings.TrimSpace(r.Header.Get("X-Real-IP")); xri != "" {
			if addr, ok := parseIP(hostOnly(xri)); ok {
				effectiveIP = addr.String()
				if !addr.IsLoopback() {
					return PeerInfo{IP: effectiveIP, IsLoopback: false, Kind: "lan"}
				}
			}
		}
		return PeerInfo{IP: effectiveIP, IsLoopback: true, Kind: "loopback"}
	}

	if remoteOK {
		effectiveIP = remoteAddr.String()
	}
	return PeerInfo{IP: effectiveIP, IsLoopback: false, Kind: "lan"}
}

func hostOnly(addr string) string {
	addr = strings.TrimSpace(addr)
	if host, _, err := net.SplitHostPort(addr); err == nil {
		return host
	}
	return strings.Trim(addr, "[]")
}

func parseIP(s string) (netip.Addr, bool) {
	addr, err := netip.ParseAddr(strings.TrimSpace(s))
	if err != nil {
		return netip.Addr{}, false
	}
	return addr.Unmap(), true
}

// ExtractSecret extracts a gateway key from Authorization Bearer, x-api-key, x-goog-api-key, or ?key=.
func ExtractSecret(r *http.Request) string {
	if auth := strings.TrimSpace(r.Header.Get("Authorization")); auth != "" {
		if len(auth) > 7 && strings.EqualFold(auth[:7], "Bearer ") {
			return strings.TrimSpace(auth[7:])
		}
	}
	if k := strings.TrimSpace(r.Header.Get("x-api-key")); k != "" {
		return k
	}
	if k := strings.TrimSpace(r.Header.Get("x-goog-api-key")); k != "" {
		return k
	}
	if k := strings.TrimSpace(r.URL.Query().Get("key")); k != "" {
		return k
	}
	return ""
}

// IPAllowed checks whether peer is permitted by allowIps (empty allows all; loopback always allowed).
func IPAllowed(peer PeerInfo, allowIps []string) bool {
	if peer.IsLoopback || len(allowIps) == 0 {
		return true
	}
	addr, ok := parseIP(peer.IP)
	if !ok {
		return false
	}
	for _, raw := range allowIps {
		raw = strings.TrimSpace(raw)
		if raw == "" {
			continue
		}
		if raw == "*" {
			return true
		}
		if strings.Contains(raw, "/") {
			if pfx, err := netip.ParsePrefix(raw); err == nil && pfx.Contains(addr) {
				return true
			}
			continue
		}
		if allowAddr, ok := parseIP(raw); ok && allowAddr == addr {
			return true
		}
	}
	return false
}

// Authenticate validates IP allowlist, key auth, and key budget limits.
// Returns (Identity, httpStatus, errorMessage). httpStatus == 0 means authorized.
func Authenticate(r *http.Request, st *store.Store, settings types.Settings) (Identity, int, string) {
	peer := ResolvePeer(r)
	if !IPAllowed(peer, settings.AllowIps) {
		return Identity{Peer: peer}, http.StatusForbidden, "IP address not in allowlist"
	}

	secret := ExtractSecret(r)
	if secret != "" {
		cfg := st.ConfigSnapshot()
		var matched *types.AccessKey
		for i := range cfg.Keys {
			k := &cfg.Keys[i]
			if k.Secret != "" && subtle.ConstantTimeCompare([]byte(secret), []byte(k.Secret)) == 1 {
				cp := *k
				matched = &cp
				break
			}
		}
		if matched == nil {
			return Identity{Peer: peer}, http.StatusUnauthorized, "Invalid gateway access key"
		}
		if !matched.Enabled {
			return Identity{Peer: peer}, http.StatusUnauthorized, "Gateway access key is disabled"
		}
		todayReqs, todayUsd, monthUsd := st.GetKeySpend(matched.ID)
		if matched.DailyLimitReqs > 0 && todayReqs >= matched.DailyLimitReqs {
			return Identity{Peer: peer, Key: matched, KeyID: matched.ID, KeyName: matched.Name}, http.StatusTooManyRequests, "Daily request limit exceeded for key"
		}
		if matched.DailyLimitUsd > 0 && todayUsd >= matched.DailyLimitUsd {
			return Identity{Peer: peer, Key: matched, KeyID: matched.ID, KeyName: matched.Name}, http.StatusTooManyRequests, "Daily spend limit exceeded for key"
		}
		if matched.MonthlyLimitUsd > 0 && monthUsd >= matched.MonthlyLimitUsd {
			return Identity{Peer: peer, Key: matched, KeyID: matched.ID, KeyName: matched.Name}, http.StatusTooManyRequests, "Monthly spend limit exceeded for key"
		}
		return Identity{
			Peer:    peer,
			Key:     matched,
			KeyID:   matched.ID,
			KeyName: matched.Name,
		}, 0, ""
	}

	if peer.IsLoopback && settings.AllowLocalKeyless {
		return Identity{
			Peer:    peer,
			Keyless: true,
			KeyName: "local-keyless",
		}, 0, ""
	}

	return Identity{Peer: peer}, http.StatusUnauthorized, "Missing gateway access key"
}

// ModelAllowed checks if an authenticated key is permitted to call requestedModel.
func ModelAllowed(id Identity, requestedModel string) bool {
	if id.Key == nil || len(id.Key.AllowedModels) == 0 {
		return true
	}
	req := strings.TrimSpace(requestedModel)
	for _, pattern := range id.Key.AllowedModels {
		p := strings.TrimSpace(pattern)
		if p == "" {
			continue
		}
		if p == "*" || p == req {
			return true
		}
		if strings.HasSuffix(p, "/*") {
			prefix := strings.TrimSuffix(p, "*")
			if strings.HasPrefix(req, prefix) {
				return true
			}
		}
	}
	return false
}

// ApplyCORS writes CORS headers based on settings.CorsOrigins. Returns true if it handled an OPTIONS preflight.
func ApplyCORS(w http.ResponseWriter, r *http.Request, origins []string) bool {
	origin := strings.TrimSpace(r.Header.Get("Origin"))
	if origin != "" && len(origins) > 0 {
		matched := ""
		for _, allowed := range origins {
			a := strings.TrimSpace(allowed)
			if a == "*" {
				matched = "*"
				break
			}
			if strings.EqualFold(a, origin) {
				matched = origin
				break
			}
		}
		if matched != "" {
			w.Header().Set("Access-Control-Allow-Origin", matched)
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, X-API-Key, X-Goog-API-Key, Anthropic-Version")
			w.Header().Set("Access-Control-Max-Age", "3600")
		}
	}
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return true
	}
	return false
}

// WriteError writes an OpenAI-compatible JSON error payload.
func WriteError(w http.ResponseWriter, status int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{
		"error": map[string]any{
			"message": msg,
			"type":    "access_error",
			"code":    status,
		},
	})
}
