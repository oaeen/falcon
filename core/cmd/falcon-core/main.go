package main

import (
	"context"
	"flag"
	"log"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/falcon-gateway/falcon/core/internal/engine"
)

func main() {
	var (
		dataDir     = flag.String("data-dir", envOr("FALCON_DATA_DIR", ""), "Falcon data directory")
		cacheDir    = flag.String("cache-dir", envOr("FALCON_CACHE_DIR", ""), "Falcon cache directory")
		gatewayPort = flag.Int("gateway-port", envIntOr("FALCON_GATEWAY_PORT", 18787), "Gateway listen port")
		adminAddr   = flag.String("admin-addr", envOr("FALCON_ADMIN_ADDR", "127.0.0.1:18788"), "Admin loopback listen address")
		adminToken  = flag.String("admin-token", envOr("FALCON_ADMIN_TOKEN", ""), "Admin API bearer token")
		bunPath     = flag.String("bun", envOr("FALCON_BUN", ""), "Path to bun binary")
		dnsServers  = flag.String("dns", envOr("FALCON_DNS", ""), "Comma-separated DNS servers")
	)
	flag.Parse()

	cfg := engine.Config{
		DataDir:     *dataDir,
		CacheDir:    *cacheDir,
		GatewayPort: *gatewayPort,
		AdminAddr:   *adminAddr,
		AdminToken:  *adminToken,
		BunPath:     *bunPath,
		DNSServers:  *dnsServers,
	}

	eng, err := engine.StartInstance(context.Background(), cfg)
	if err != nil {
		log.Fatalf("falcon-core failed to start: %v", err)
	}
	st := eng.Status()
	log.Printf("falcon-core started: gateway=%s admin=%s pluginMode=%s", st.ListenAddr, eng.AdminAddr(), st.PluginRuntimeMode)

	sigCh := make(chan os.Signal, 2)
	signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)
	<-sigCh

	log.Printf("falcon-core shutting down...")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := eng.Stop(ctx); err != nil {
		log.Printf("falcon-core shutdown warning: %v", err)
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func envIntOr(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			return n
		}
	}
	return fallback
}
