package engine

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/falcon-gateway/falcon/core/internal/admin"
	"github.com/falcon-gateway/falcon/core/internal/cabundle"
	"github.com/falcon-gateway/falcon/core/internal/gateway"
	"github.com/falcon-gateway/falcon/core/internal/plugin"
	"github.com/falcon-gateway/falcon/core/internal/router"
	"github.com/falcon-gateway/falcon/core/internal/store"
	"github.com/falcon-gateway/falcon/core/internal/types"
)

// Config holds startup parameters for the Falcon core engine.
type Config struct {
	DataDir     string
	CacheDir    string
	GatewayPort int
	AdminAddr   string
	AdminToken  string
	BunPath     string
	DNSServers  string
}

// Engine encapsulates the full Falcon lifecycle (Store, Plugins, Gateway, Admin).
type Engine struct {
	store   *store.Store
	router  *router.Router
	plugins *plugin.Manager
	gateway *gateway.Server
	admin   *admin.Server
}

var (
	globalMu     sync.Mutex
	globalEngine *Engine
)

// Start launches the singleton Engine using cfg.
func Start(cfg Config) error {
	globalMu.Lock()
	defer globalMu.Unlock()
	if globalEngine != nil {
		return nil
	}
	eng, err := StartInstance(context.Background(), cfg)
	if err != nil {
		return err
	}
	globalEngine = eng
	return nil
}

// Stop gracefully shuts down the singleton Engine.
func Stop() error {
	globalMu.Lock()
	eng := globalEngine
	globalEngine = nil
	globalMu.Unlock()
	if eng == nil {
		return nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	return eng.Stop(ctx)
}

// Status returns the current GatewayStatus of the singleton Engine.
func Status() types.GatewayStatus {
	globalMu.Lock()
	eng := globalEngine
	globalMu.Unlock()
	if eng == nil {
		return types.GatewayStatus{
			Running:           false,
			LanUrls:           []string{},
			PluginRuntimeMode: "embedded",
		}
	}
	return eng.Status()
}

// StartInstance initializes and starts a new Engine instance.
func StartInstance(ctx context.Context, cfg Config) (*Engine, error) {
	if strings.TrimSpace(cfg.DataDir) == "" {
		home, _ := os.UserHomeDir()
		if home == "" {
			home = "."
		}
		cfg.DataDir = filepath.Join(home, ".falcon")
	}
	if strings.TrimSpace(cfg.CacheDir) == "" {
		cfg.CacheDir = filepath.Join(cfg.DataDir, "cache")
	}
	if strings.TrimSpace(cfg.AdminAddr) == "" {
		cfg.AdminAddr = "127.0.0.1:18788"
	}

	caPath, _ := cabundle.Build(cfg.CacheDir)
	if caPath != "" {
		if os.Getenv("SSL_CERT_FILE") == "" {
			_ = os.Setenv("SSL_CERT_FILE", caPath)
		}
		if os.Getenv("NODE_EXTRA_CA_CERTS") == "" {
			_ = os.Setenv("NODE_EXTRA_CA_CERTS", caPath)
		}
	}

	httpClient := buildHTTPClient(caPath, cfg.DNSServers)

	st, err := store.Open(cfg.DataDir)
	if err != nil {
		return nil, err
	}
	if cfg.GatewayPort > 0 && cfg.GatewayPort <= 65535 {
		p := cfg.GatewayPort
		if st.Settings().Port != p {
			_, _, _ = st.UpdateSettings(types.SettingsPatch{Port: &p})
		}
	}

	rt := router.New()
	pm := plugin.NewManager(st, cfg.BunPath, cfg.CacheDir, caPath, cfg.DNSServers, httpClient)
	_ = pm.Reload(ctx)

	gw := gateway.New(st, rt, pm, httpClient)
	if err := gw.Start(); err != nil {
		pm.Stop()
		return nil, err
	}

	adm := admin.New(st, gw, pm, cfg.AdminAddr, cfg.AdminToken, httpClient)
	if err := adm.Start(); err != nil {
		_ = gw.Stop(ctx)
		pm.Stop()
		return nil, err
	}

	return &Engine{
		store:   st,
		router:  rt,
		plugins: pm,
		gateway: gw,
		admin:   adm,
	}, nil
}

// Stop gracefully stops admin, gateway, and plugin host.
func (e *Engine) Stop(ctx context.Context) error {
	if e == nil {
		return nil
	}
	var errs []error
	if e.admin != nil {
		if err := e.admin.Stop(ctx); err != nil {
			errs = append(errs, err)
		}
	}
	if e.gateway != nil {
		if err := e.gateway.Stop(ctx); err != nil {
			errs = append(errs, err)
		}
	}
	if e.plugins != nil {
		e.plugins.Stop()
	}
	return errors.Join(errs...)
}

// Status returns the current GatewayStatus snapshot.
func (e *Engine) Status() types.GatewayStatus {
	if e == nil || e.gateway == nil {
		return types.GatewayStatus{LanUrls: []string{}, PluginRuntimeMode: "embedded"}
	}
	return e.gateway.Status()
}

// AdminAddr returns the bound admin listen address.
func (e *Engine) AdminAddr() string {
	if e == nil || e.admin == nil {
		return ""
	}
	return e.admin.Addr()
}

func buildHTTPClient(caPath, dnsServers string) *http.Client {
	tr := http.DefaultTransport.(*http.Transport).Clone()
	if caPath != "" {
		if pemData, err := os.ReadFile(caPath); err == nil {
			pool, err := x509.SystemCertPool()
			if err != nil || pool == nil {
				pool = x509.NewCertPool()
			}
			pool.AppendCertsFromPEM(pemData)
			if tr.TLSClientConfig != nil {
				tr.TLSClientConfig.RootCAs = pool
			} else {
				tr.TLSClientConfig = &tls.Config{RootCAs: pool}
			}
		}
	}
	var dnsList []string
	for _, s := range strings.Split(dnsServers, ",") {
		s = strings.TrimSpace(s)
		if net.ParseIP(s) != nil {
			dnsList = append(dnsList, net.JoinHostPort(s, "53"))
		}
	}
	if len(dnsList) > 0 {
		dialer := &net.Dialer{
			Timeout:   15 * time.Second,
			KeepAlive: 30 * time.Second,
			Resolver: &net.Resolver{
				PreferGo: true,
				Dial: func(ctx context.Context, network, _ string) (net.Conn, error) {
					d := net.Dialer{Timeout: 5 * time.Second}
					var lastErr error
					for _, srv := range dnsList {
						c, err := d.DialContext(ctx, network, srv)
						if err == nil {
							return c, nil
						}
						lastErr = err
					}
					return nil, lastErr
				},
			},
		}
		tr.DialContext = dialer.DialContext
	}
	return &http.Client{
		Transport: tr,
		Timeout:   5 * time.Minute,
	}
}
