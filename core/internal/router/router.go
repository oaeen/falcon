package router

import (
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/falcon-gateway/falcon/core/internal/types"
)

// Target represents one resolved upstream execution candidate.
type Target struct {
	ProviderID string
	ModelID    string
	Raw        string // "<provider>/<model>"
	IsPlugin   bool
}

// PluginProviderLookup resolves plugin-provided models when routing.
type PluginProviderLookup interface {
	HasModel(providerID, modelID string) bool
	FindProvidersForModel(modelID string) []string
}

// Router handles model alias resolution, routing groups, cooldown failover, and TTFT EWMA tracking.
type Router struct {
	mu       sync.RWMutex
	ttftEWMA map[string]float64   // target -> ms
	cooldown map[string]time.Time // target -> cooldown until
	rrCount  map[string]*atomic.Uint64
}

// New creates a new Router.
func New() *Router {
	return &Router{
		ttftEWMA: make(map[string]float64),
		cooldown: make(map[string]time.Time),
		rrCount:  make(map[string]*atomic.Uint64),
	}
}

// Resolve expands aliases, routing groups, or bare model names into an ordered slice of failover Targets.
func (r *Router) Resolve(cfg types.Config, pluginLookup PluginProviderLookup, requestedModel string) []Target {
	model := strings.TrimSpace(requestedModel)
	if model == "" {
		return nil
	}

	// 1. Resolve aliases (max 4 hops to avoid cycles)
	seenAlias := map[string]bool{}
	for i := 0; i < 4; i++ {
		if seenAlias[model] {
			break
		}
		seenAlias[model] = true
		next, ok := cfg.Aliases[model]
		if !ok || strings.TrimSpace(next) == "" {
			break
		}
		model = strings.TrimSpace(next)
	}

	// Build enabled API provider map
	apiProviders := make(map[string]types.Provider, len(cfg.Providers))
	for _, p := range cfg.Providers {
		if p.Enabled {
			apiProviders[p.ID] = p
		}
	}

	makeTarget := func(spec string) (Target, bool) {
		spec = strings.TrimSpace(spec)
		if spec == "" {
			return Target{}, false
		}
		provID, modID, hasSlash := strings.Cut(spec, "/")
		if !hasSlash {
			return Target{}, false
		}
		if p, ok := apiProviders[provID]; ok {
			if len(p.Keys) > 0 || p.Protocol == types.ProtocolOllama {
				return Target{ProviderID: provID, ModelID: modID, Raw: spec, IsPlugin: false}, true
			}
		}
		if pluginLookup != nil && pluginLookup.HasModel(provID, modID) {
			return Target{ProviderID: provID, ModelID: modID, Raw: spec, IsPlugin: true}, true
		}
		return Target{}, false
	}

	// 2. Check routing groups
	groupName := strings.TrimPrefix(model, "group/")
	for _, g := range cfg.Groups {
		if !g.Enabled {
			continue
		}
		if g.Name == groupName || g.ID == model || "group/"+g.Name == model {
			orderedSpecs := r.orderGroupTargets(g)
			var out []Target
			for _, spec := range orderedSpecs {
				if t, ok := makeTarget(spec); ok {
					out = append(out, t)
				}
			}
			return r.applyCooldownOrder(out)
		}
	}

	// 3. Explicit <provider>/<model>
	if provID, modID, hasSlash := strings.Cut(model, "/"); hasSlash {
		if t, ok := makeTarget(provID + "/" + modID); ok {
			return []Target{t}
		}
		// Some OpenRouter / SiliconFlow models themselves contain '/' (e.g. "openai/gpt-4o-mini").
		// Fall through to bare model search across providers!
	}

	// 4. Bare model search across enabled API providers then plugin providers
	var out []Target
	for _, p := range cfg.Providers {
		if !p.Enabled {
			continue
		}
		if len(p.Keys) == 0 && p.Protocol != types.ProtocolOllama {
			continue
		}
		for _, m := range p.ActiveModels() {
			if m == model {
				out = append(out, Target{
					ProviderID: p.ID,
					ModelID:    m,
					Raw:        p.ID + "/" + m,
					IsPlugin:   false,
				})
				break
			}
		}
	}
	if pluginLookup != nil {
		for _, pid := range pluginLookup.FindProvidersForModel(model) {
			out = append(out, Target{
				ProviderID: pid,
				ModelID:    model,
				Raw:        pid + "/" + model,
				IsPlugin:   true,
			})
		}
	}
	return r.applyCooldownOrder(out)
}

func (r *Router) orderGroupTargets(g types.RoutingGroup) []string {
	targets := append([]string{}, g.Targets...)
	if len(targets) <= 1 {
		return targets
	}
	switch g.Strategy {
	case types.StrategyManual:
		if g.PinnedTarget != "" {
			out := []string{g.PinnedTarget}
			for _, t := range targets {
				if t != g.PinnedTarget {
					out = append(out, t)
				}
			}
			return out
		}
		return targets

	case types.StrategyRoundRobin:
		r.mu.Lock()
		ctr := r.rrCount[g.ID]
		if ctr == nil {
			ctr = &atomic.Uint64{}
			r.rrCount[g.ID] = ctr
		}
		r.mu.Unlock()
		idx := int((ctr.Add(1) - 1) % uint64(len(targets)))
		out := make([]string, 0, len(targets))
		out = append(out, targets[idx:]...)
		out = append(out, targets[:idx]...)
		return out

	case types.StrategyFastest:
		r.mu.RLock()
		scores := make(map[string]float64, len(targets))
		for _, t := range targets {
			if ewma, ok := r.ttftEWMA[t]; ok {
				scores[t] = ewma
			} else {
				scores[t] = 0 // unseen targets get probed early
			}
		}
		r.mu.RUnlock()
		sort.SliceStable(targets, func(i, j int) bool {
			return scores[targets[i]] < scores[targets[j]]
		})
		return targets

	default: // StrategyOrder
		return targets
	}
}

func (r *Router) applyCooldownOrder(targets []Target) []Target {
	if len(targets) <= 1 {
		return targets
	}
	now := time.Now()
	r.mu.RLock()
	defer r.mu.RUnlock()

	var ready, cooled []Target
	for _, t := range targets {
		if until, ok := r.cooldown[t.Raw]; ok && now.Before(until) {
			cooled = append(cooled, t)
		} else {
			ready = append(ready, t)
		}
	}
	return append(ready, cooled...)
}

// RecordTTFT updates the EWMA TTFT for a target and clears any active cooldown.
func (r *Router) RecordTTFT(target string, ttftMs int64) {
	if target == "" || ttftMs <= 0 {
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.cooldown, target)
	prev, ok := r.ttftEWMA[target]
	if !ok {
		r.ttftEWMA[target] = float64(ttftMs)
		return
	}
	const alpha = 0.3
	r.ttftEWMA[target] = alpha*float64(ttftMs) + (1-alpha)*prev
}

// RecordFailure places a target in cooldown when upstream returns 429 or 5xx.
func (r *Router) RecordFailure(target string, statusCode int) {
	if target == "" {
		return
	}
	var d time.Duration
	switch {
	case statusCode == 429:
		d = 60 * time.Second
	case statusCode >= 500 || statusCode == 0:
		d = 30 * time.Second
	default:
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	r.cooldown[target] = time.Now().Add(d)
}

// EWMA returns the current tracked TTFT EWMA in ms for a target (0 if unknown).
func (r *Router) EWMA(target string) float64 {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.ttftEWMA[target]
}
