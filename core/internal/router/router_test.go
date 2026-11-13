package router

import (
	"testing"

	"github.com/falcon-gateway/falcon/core/internal/types"
)

func TestRouterStrategiesAndCooldown(t *testing.T) {
	cfg := types.DefaultConfig()
	cfg.Providers = []types.Provider{
		{
			ID: "p1", Name: "P1", Protocol: types.ProtocolOpenAI, Enabled: true,
			Keys:   []types.ProviderKey{{ID: "k1", Secret: "sk-1", Enabled: true, Weight: 1}},
			Models: []string{"m1"},
		},
		{
			ID: "p2", Name: "P2", Protocol: types.ProtocolOpenAI, Enabled: true,
			Keys:   []types.ProviderKey{{ID: "k2", Secret: "sk-2", Enabled: true, Weight: 1}},
			Models: []string{"m2"},
		},
	}
	cfg.Aliases = map[string]string{
		"gpt-4o": "fast-group",
	}
	cfg.Groups = []types.RoutingGroup{
		{
			ID:       "g1",
			Name:     "fast-group",
			Strategy: types.StrategyFastest,
			Targets:  []string{"p1/m1", "p2/m2"},
			Enabled:  true,
		},
		{
			ID:       "g2",
			Name:     "rr-group",
			Strategy: types.StrategyRoundRobin,
			Targets:  []string{"p1/m1", "p2/m2"},
			Enabled:  true,
		},
	}

	rt := New()
	rt.RecordTTFT("p1/m1", 500)
	rt.RecordTTFT("p2/m2", 120)

	// Fastest picks p2/m2 first via alias -> group
	targets := rt.Resolve(cfg, nil, "gpt-4o")
	if len(targets) != 2 || targets[0].Raw != "p2/m2" {
		t.Fatalf("expected p2/m2 fastest first, got %+v", targets)
	}

	// Cooldown puts p2/m2 behind p1/m1
	rt.RecordFailure("p2/m2", 429)
	targets = rt.Resolve(cfg, nil, "gpt-4o")
	if targets[0].Raw != "p1/m1" {
		t.Fatalf("expected p1/m1 first during p2/m2 cooldown, got %+v", targets)
	}

	// RecordTTFT clears cooldown, allowing round robin to alternate
	rt.RecordTTFT("p2/m2", 120)
	rr1 := rt.Resolve(cfg, nil, "rr-group")
	rr2 := rt.Resolve(cfg, nil, "rr-group")
	if rr1[0].Raw == rr2[0].Raw {
		t.Fatalf("expected round robin to alternate, got %s twice", rr1[0].Raw)
	}
}
