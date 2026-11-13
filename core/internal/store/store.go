package store

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/falcon-gateway/falcon/core/internal/types"
)

const MaxLogEntries = 500

// Store manages thread-safe atomic JSON persistence for config.json and usage.json.
type Store struct {
	mu        sync.RWMutex
	dataDir   string
	cfg       types.Config
	usage     types.UsageStore
	startedAt time.Time
}

// Open initializes the store in dataDir, loading existing config.json and usage.json if present.
func Open(dataDir string) (*Store, error) {
	if strings.TrimSpace(dataDir) == "" {
		return nil, errors.New("dataDir must not be empty")
	}
	if err := os.MkdirAll(dataDir, 0o700); err != nil {
		return nil, err
	}
	s := &Store{
		dataDir:   dataDir,
		cfg:       types.DefaultConfig(),
		usage:     types.NewUsageStore(),
		startedAt: time.Now(),
	}
	if err := s.loadConfig(); err != nil {
		return nil, err
	}
	if err := s.loadUsage(); err != nil {
		return nil, err
	}
	return s, nil
}

func (s *Store) DataDir() string { return s.dataDir }

func (s *Store) ConfigPath() string { return filepath.Join(s.dataDir, "config.json") }

func (s *Store) UsagePath() string { return filepath.Join(s.dataDir, "usage.json") }

func (s *Store) UptimeSec() int64 {
	return int64(time.Since(s.startedAt).Seconds())
}

func (s *Store) loadConfig() error {
	raw, err := os.ReadFile(s.ConfigPath())
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return s.saveConfigLocked()
		}
		return err
	}
	var cfg types.Config
	if err := json.Unmarshal(raw, &cfg); err != nil {
		return fmt.Errorf("parse config.json: %w", err)
	}
	normalizeConfig(&cfg)
	s.cfg = cfg
	return nil
}

func (s *Store) loadUsage() error {
	raw, err := os.ReadFile(s.UsagePath())
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return s.saveUsageLocked()
		}
		return err
	}
	var u types.UsageStore
	if err := json.Unmarshal(raw, &u); err != nil {
		return fmt.Errorf("parse usage.json: %w", err)
	}
	normalizeUsage(&u)
	s.usage = u
	return nil
}

func normalizeConfig(cfg *types.Config) {
	if cfg.Version == 0 {
		cfg.Version = 1
	}
	if cfg.Settings.Port <= 0 || cfg.Settings.Port > 65535 {
		cfg.Settings.Port = 18787
	}
	if cfg.Settings.AllowIps == nil {
		cfg.Settings.AllowIps = []string{}
	}
	if cfg.Settings.CorsOrigins == nil {
		cfg.Settings.CorsOrigins = []string{}
	}
	if cfg.Settings.RedactRules == nil {
		cfg.Settings.RedactRules = []types.RedactRule{}
	}
	for i := range cfg.Settings.RedactRules {
		if cfg.Settings.RedactRules[i].Replacement == "" {
			cfg.Settings.RedactRules[i].Replacement = cfg.Settings.RedactRules[i].Placeholder
		} else if cfg.Settings.RedactRules[i].Placeholder == "" {
			cfg.Settings.RedactRules[i].Placeholder = cfg.Settings.RedactRules[i].Replacement
		}
	}
	if cfg.Settings.RedactAllow == nil {
		cfg.Settings.RedactAllow = []string{}
	}
	if cfg.Keys == nil {
		cfg.Keys = []types.AccessKey{}
	}
	for i := range cfg.Keys {
		if cfg.Keys[i].AllowedModels == nil {
			cfg.Keys[i].AllowedModels = []string{}
		}
		if cfg.Keys[i].Secret != "" {
			cfg.Keys[i].Masked = types.MaskSecret(cfg.Keys[i].Secret)
			cfg.Keys[i].Prefix = cfg.Keys[i].Masked
		}
	}
	if cfg.Providers == nil {
		cfg.Providers = []types.Provider{}
	}
	for i := range cfg.Providers {
		if cfg.Providers[i].Keys == nil {
			cfg.Providers[i].Keys = []types.ProviderKey{}
		}
		if cfg.Providers[i].Models == nil {
			cfg.Providers[i].Models = []string{}
		}
		if len(cfg.Providers[i].Models) == 0 && len(cfg.Providers[i].SelectedModels) > 0 {
			cfg.Providers[i].Models = append([]string{}, cfg.Providers[i].SelectedModels...)
		} else if cfg.Providers[i].SelectedModels == nil && len(cfg.Providers[i].Models) > 0 {
			cfg.Providers[i].SelectedModels = append([]string{}, cfg.Providers[i].Models...)
		}
		for j := range cfg.Providers[i].Keys {
			if cfg.Providers[i].Keys[j].Weight <= 0 {
				cfg.Providers[i].Keys[j].Weight = 1
			}
			if cfg.Providers[i].Keys[j].Secret != "" {
				cfg.Providers[i].Keys[j].Masked = types.MaskSecret(cfg.Providers[i].Keys[j].Secret)
				cfg.Providers[i].Keys[j].MaskedSecret = cfg.Providers[i].Keys[j].Masked
			}
		}
	}
	if cfg.Groups == nil {
		cfg.Groups = []types.RoutingGroup{}
	}
	for i := range cfg.Groups {
		if cfg.Groups[i].Targets == nil {
			cfg.Groups[i].Targets = []string{}
		}
		if cfg.Groups[i].Strategy == "" {
			cfg.Groups[i].Strategy = types.StrategyOrder
		}
	}
	if cfg.Aliases == nil {
		cfg.Aliases = map[string]string{}
	}
	if cfg.Plugins == nil {
		cfg.Plugins = []types.InstalledPluginEntry{}
	}
}

func normalizeUsage(u *types.UsageStore) {
	if u.Version == 0 {
		u.Version = 1
	}
	if u.Daily == nil {
		u.Daily = map[string]*types.DailyBucket{}
	}
	if u.KeyDaily == nil {
		u.KeyDaily = map[string]*types.KeyUsageDay{}
	}
	if u.KeyMonthly == nil {
		u.KeyMonthly = map[string]float64{}
	}
	if u.RedactByKind == nil {
		u.RedactByKind = map[string]int64{}
	}
	if u.Logs == nil {
		u.Logs = []types.RequestLogEntry{}
	}
	if len(u.Logs) > MaxLogEntries {
		u.Logs = u.Logs[:MaxLogEntries]
	}
}

func (s *Store) saveConfigLocked() error {
	return WriteAtomicJSON(s.ConfigPath(), s.cfg)
}

func (s *Store) saveUsageLocked() error {
	return WriteAtomicJSON(s.UsagePath(), s.usage)
}

// WriteAtomicJSON writes v as indented JSON atomically via temp file + rename.
func WriteAtomicJSON(path string, v any) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	tmp, err := os.CreateTemp(dir, ".tmp-*.json")
	if err != nil {
		return err
	}
	tmpPath := tmp.Name()
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		_ = os.Remove(tmpPath)
		return err
	}
	if err := tmp.Chmod(0o600); err != nil {
		_ = tmp.Close()
		_ = os.Remove(tmpPath)
		return err
	}
	if err := tmp.Sync(); err != nil {
		_ = tmp.Close()
		_ = os.Remove(tmpPath)
		return err
	}
	if err := tmp.Close(); err != nil {
		_ = os.Remove(tmpPath)
		return err
	}
	if err := os.Rename(tmpPath, path); err != nil {
		_ = os.Remove(tmpPath)
		return err
	}
	return nil
}

// ConfigSnapshot returns a deep copy of the current configuration.
func (s *Store) ConfigSnapshot() types.Config {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return cloneConfig(s.cfg)
}

func cloneConfig(c types.Config) types.Config {
	b, _ := json.Marshal(c)
	var out types.Config
	_ = json.Unmarshal(b, &out)
	normalizeConfig(&out)
	return out
}

// Settings returns a copy of current Settings.
func (s *Store) Settings() types.Settings {
	return s.ConfigSnapshot().Settings
}

// UpdateSettings applies a partial patch to settings and persists atomically.
func (s *Store) UpdateSettings(patch types.SettingsPatch) (types.Settings, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	prevPort := s.cfg.Settings.Port
	prevLAN := s.cfg.Settings.LanEnabled

	if patch.Port != nil {
		if *patch.Port < 1 || *patch.Port > 65535 {
			return s.cfg.Settings, false, fmt.Errorf("invalid port: %d", *patch.Port)
		}
		s.cfg.Settings.Port = *patch.Port
	}
	if patch.LanEnabled != nil {
		s.cfg.Settings.LanEnabled = *patch.LanEnabled
	}
	if patch.AllowLocalKeyless != nil {
		s.cfg.Settings.AllowLocalKeyless = *patch.AllowLocalKeyless
	}
	if patch.AllowIps != nil {
		s.cfg.Settings.AllowIps = append([]string{}, (*patch.AllowIps)...)
	}
	if patch.CorsOrigins != nil {
		s.cfg.Settings.CorsOrigins = append([]string{}, (*patch.CorsOrigins)...)
	}
	if patch.RedactEnabled != nil {
		s.cfg.Settings.RedactEnabled = *patch.RedactEnabled
	}
	if patch.RedactRestore != nil {
		s.cfg.Settings.RedactRestore = *patch.RedactRestore
	}
	if patch.RedactRules != nil {
		s.cfg.Settings.RedactRules = append([]types.RedactRule{}, (*patch.RedactRules)...)
	}
	if patch.RedactAllow != nil {
		s.cfg.Settings.RedactAllow = append([]string{}, (*patch.RedactAllow)...)
	}
	if patch.ChinaMirror != nil {
		s.cfg.Settings.ChinaMirror = *patch.ChinaMirror
	}
	normalizeConfig(&s.cfg)
	if err := s.saveConfigLocked(); err != nil {
		return s.cfg.Settings, false, err
	}
	relisten := s.cfg.Settings.Port != prevPort || s.cfg.Settings.LanEnabled != prevLAN
	return cloneSettings(s.cfg.Settings), relisten, nil
}

func cloneSettings(st types.Settings) types.Settings {
	b, _ := json.Marshal(st)
	var out types.Settings
	_ = json.Unmarshal(b, &out)
	return out
}

// NewID generates a random hex ID.
func NewID(prefix string) string {
	var b [8]byte
	_, _ = rand.Read(b[:])
	if prefix == "" {
		return hex.EncodeToString(b[:])
	}
	return prefix + "-" + hex.EncodeToString(b[:])
}

// NewGatewaySecret generates a sk-flc-... gateway key secret.
func NewGatewaySecret() string {
	var b [20]byte
	_, _ = rand.Read(b[:])
	return "sk-flc-" + hex.EncodeToString(b[:])
}

// ListKeysMasked returns all access keys with secrets stripped (masked kept) and spend attached.
func (s *Store) ListKeysMasked() []types.AccessKey {
	s.mu.RLock()
	defer s.mu.RUnlock()
	today := time.Now().Format("2006-01-02")
	month := time.Now().Format("2006-01")
	out := make([]types.AccessKey, len(s.cfg.Keys))
	for i, k := range s.cfg.Keys {
		cp := k
		cp.AllowedModels = append([]string{}, k.AllowedModels...)
		cp.Masked = types.MaskSecret(k.Secret)
		cp.Prefix = cp.Masked
		cp.Secret = ""
		if d, ok := s.usage.KeyDaily[k.ID+"|"+today]; ok {
			cp.TodayReqs = d.Requests
			cp.TodayUsd = d.EstimatedUsd
		}
		cp.MonthUsd = s.usage.KeyMonthly[k.ID+"|"+month]
		out[i] = cp
	}
	return out
}

// CreateOrUpdateKey creates a new access key (returning full secret) or updates an existing key by ID.
func (s *Store) CreateOrUpdateKey(in types.AccessKey) (types.AccessKey, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if in.AllowedModels == nil {
		in.AllowedModels = []string{}
	}
	for i, existing := range s.cfg.Keys {
		if in.ID != "" && existing.ID == in.ID {
			updated := existing
			if strings.TrimSpace(in.Name) != "" {
				updated.Name = strings.TrimSpace(in.Name)
			}
			updated.Enabled = in.Enabled
			updated.AllowedModels = append([]string{}, in.AllowedModels...)
			updated.DailyLimitUsd = in.DailyLimitUsd
			updated.MonthlyLimitUsd = in.MonthlyLimitUsd
			updated.DailyLimitReqs = in.DailyLimitReqs
			updated.Masked = types.MaskSecret(updated.Secret)
			updated.Prefix = updated.Masked
			s.cfg.Keys[i] = updated
			if err := s.saveConfigLocked(); err != nil {
				return types.AccessKey{}, false, err
			}
			res := updated
			res.Secret = ""
			return res, false, nil
		}
	}

	if in.ID == "" {
		in.ID = NewID("key")
	}
	if strings.TrimSpace(in.Name) == "" {
		in.Name = "Gateway Key"
	}
	if in.Secret == "" {
		in.Secret = NewGatewaySecret()
	}
	in.Masked = types.MaskSecret(in.Secret)
	in.Prefix = in.Masked
	if in.CreatedAt == "" {
		in.CreatedAt = types.NowRFC3339()
	}
	s.cfg.Keys = append(s.cfg.Keys, in)
	if err := s.saveConfigLocked(); err != nil {
		return types.AccessKey{}, false, err
	}
	return in, true, nil
}

// DeleteKey removes an access key by ID.
func (s *Store) DeleteKey(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i, k := range s.cfg.Keys {
		if k.ID == id {
			s.cfg.Keys = append(s.cfg.Keys[:i], s.cfg.Keys[i+1:]...)
			return s.saveConfigLocked()
		}
	}
	return errors.New("key not found")
}

// RotateKey issues a fresh secret for an existing key ID and returns the full updated key.
func (s *Store) RotateKey(id string) (types.AccessKey, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i, k := range s.cfg.Keys {
		if k.ID == id {
			k.Secret = NewGatewaySecret()
			k.Masked = types.MaskSecret(k.Secret)
			k.Prefix = k.Masked
			s.cfg.Keys[i] = k
			if err := s.saveConfigLocked(); err != nil {
				return types.AccessKey{}, err
			}
			return k, nil
		}
	}
	return types.AccessKey{}, errors.New("key not found")
}

// FindKeyBySecret looks up an access key by its full secret.
func (s *Store) FindKeyBySecret(secret string) (types.AccessKey, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, k := range s.cfg.Keys {
		if k.Secret != "" && k.Secret == secret {
			return k, true
		}
	}
	return types.AccessKey{}, false
}

// GetKeySpend returns today's request count, today's USD spend, and current month's USD spend.
func (s *Store) GetKeySpend(keyID string) (int64, float64, float64) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	today := time.Now().Format("2006-01-02")
	month := time.Now().Format("2006-01")
	var reqs int64
	var todayUsd float64
	if d, ok := s.usage.KeyDaily[keyID+"|"+today]; ok {
		reqs = d.Requests
		todayUsd = d.EstimatedUsd
	}
	return reqs, todayUsd, s.usage.KeyMonthly[keyID+"|"+month]
}

// ListProvidersMasked returns providers with key secrets redacted to masked only.
func (s *Store) ListProvidersMasked() []types.Provider {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]types.Provider, len(s.cfg.Providers))
	for i, p := range s.cfg.Providers {
		cp := p
		cp.Models = append([]string{}, p.Models...)
		if p.SelectedModels != nil {
			cp.SelectedModels = append([]string{}, p.SelectedModels...)
		} else {
			cp.SelectedModels = append([]string{}, p.Models...)
		}
		cp.AvailableModels = append([]string{}, p.AvailableModels...)
		cp.Keys = make([]types.ProviderKey, len(p.Keys))
		for j, k := range p.Keys {
			kc := k
			kc.Masked = types.MaskSecret(k.Secret)
			kc.MaskedSecret = kc.Masked
			kc.Secret = ""
			cp.Keys[j] = kc
		}
		out[i] = cp
	}
	return out
}

// GetProvider returns a full provider (including secrets) by ID.
func (s *Store) GetProvider(id string) (types.Provider, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, p := range s.cfg.Providers {
		if p.ID == id {
			return p, true
		}
	}
	return types.Provider{}, false
}

// UpsertProvider creates or updates a provider, preserving existing key secrets if omitted on update.
func (s *Store) UpsertProvider(in types.Provider) (types.Provider, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if in.ID == "" {
		in.ID = NewID("prov")
	}
	if in.Models == nil {
		in.Models = []string{}
	}
	if len(in.Models) == 0 && len(in.SelectedModels) > 0 {
		in.Models = append([]string{}, in.SelectedModels...)
	} else if in.SelectedModels == nil && len(in.Models) > 0 {
		in.SelectedModels = append([]string{}, in.Models...)
	}
	if in.Keys == nil {
		in.Keys = []types.ProviderKey{}
	}

	var prevKeys map[string]string
	existingIdx := -1
	for i, p := range s.cfg.Providers {
		if p.ID == in.ID {
			existingIdx = i
			prevKeys = make(map[string]string, len(p.Keys))
			for _, k := range p.Keys {
				prevKeys[k.ID] = k.Secret
			}
			if in.LastTest == nil {
				in.LastTest = p.LastTest
			}
			if len(in.AvailableModels) == 0 && len(p.AvailableModels) > 0 {
				in.AvailableModels = append([]string{}, p.AvailableModels...)
			}
			break
		}
	}

	for i := range in.Keys {
		if in.Keys[i].ID == "" {
			in.Keys[i].ID = NewID("pk")
		}
		if in.Keys[i].Weight <= 0 {
			in.Keys[i].Weight = 1
		}
		if in.Keys[i].Secret == "" && prevKeys != nil {
			in.Keys[i].Secret = prevKeys[in.Keys[i].ID]
		}
		in.Keys[i].Masked = types.MaskSecret(in.Keys[i].Secret)
		in.Keys[i].MaskedSecret = in.Keys[i].Masked
	}

	if existingIdx >= 0 {
		s.cfg.Providers[existingIdx] = in
	} else {
		s.cfg.Providers = append(s.cfg.Providers, in)
	}
	if err := s.saveConfigLocked(); err != nil {
		return types.Provider{}, err
	}
	masked := in
	masked.Keys = make([]types.ProviderKey, len(in.Keys))
	for i, k := range in.Keys {
		k.Secret = ""
		masked.Keys[i] = k
	}
	return masked, nil
}

// DeleteProvider removes a provider by ID.
func (s *Store) DeleteProvider(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i, p := range s.cfg.Providers {
		if p.ID == id {
			s.cfg.Providers = append(s.cfg.Providers[:i], s.cfg.Providers[i+1:]...)
			return s.saveConfigLocked()
		}
	}
	return errors.New("provider not found")
}

// UpdateProviderTest saves the latest connectivity test result.
func (s *Store) UpdateProviderTest(id string, res types.ProviderTestResult) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.cfg.Providers {
		if s.cfg.Providers[i].ID == id {
			cp := res
			s.cfg.Providers[i].LastTest = &cp
			_ = s.saveConfigLocked()
			return
		}
	}
}

// UpdateProviderAvailableModels records discovered upstream models.
func (s *Store) UpdateProviderAvailableModels(id string, models []string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.cfg.Providers {
		if s.cfg.Providers[i].ID == id {
			s.cfg.Providers[i].AvailableModels = append([]string{}, models...)
			if len(s.cfg.Providers[i].Models) == 0 && len(models) > 0 {
				limit := min(len(models), 10)
				s.cfg.Providers[i].Models = append([]string{}, models[:limit]...)
				if s.cfg.Providers[i].SelectedModels == nil {
					s.cfg.Providers[i].SelectedModels = append([]string{}, models[:limit]...)
				}
			}
			return s.saveConfigLocked()
		}
	}
	return errors.New("provider not found")
}

// UpsertGroup creates or updates a routing group.
func (s *Store) UpsertGroup(g types.RoutingGroup) (types.RoutingGroup, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if g.ID == "" {
		g.ID = NewID("grp")
	}
	if g.Strategy == "" {
		g.Strategy = types.StrategyOrder
	}
	if g.Targets == nil {
		g.Targets = []string{}
	}
	for i, ex := range s.cfg.Groups {
		if ex.ID == g.ID {
			s.cfg.Groups[i] = g
			return g, s.saveConfigLocked()
		}
	}
	s.cfg.Groups = append(s.cfg.Groups, g)
	return g, s.saveConfigLocked()
}

// DeleteGroup removes a routing group.
func (s *Store) DeleteGroup(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i, g := range s.cfg.Groups {
		if g.ID == id {
			s.cfg.Groups = append(s.cfg.Groups[:i], s.cfg.Groups[i+1:]...)
			return s.saveConfigLocked()
		}
	}
	return errors.New("group not found")
}

// SetAliases replaces all aliases or updates/deletes individual aliases.
func (s *Store) SetAliases(aliases map[string]string) (map[string]string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	clean := make(map[string]string, len(aliases))
	for k, v := range aliases {
		k = strings.TrimSpace(k)
		v = strings.TrimSpace(v)
		if k != "" && v != "" {
			clean[k] = v
		}
	}
	s.cfg.Aliases = clean
	if err := s.saveConfigLocked(); err != nil {
		return nil, err
	}
	out := make(map[string]string, len(clean))
	for k, v := range clean {
		out[k] = v
	}
	return out, nil
}

// UpsertAlias sets or removes a single alias.
func (s *Store) UpsertAlias(alias, target string) (map[string]string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	alias = strings.TrimSpace(alias)
	target = strings.TrimSpace(target)
	if alias == "" {
		return nil, errors.New("alias must not be empty")
	}
	if target == "" {
		delete(s.cfg.Aliases, alias)
	} else {
		s.cfg.Aliases[alias] = target
	}
	if err := s.saveConfigLocked(); err != nil {
		return nil, err
	}
	out := make(map[string]string, len(s.cfg.Aliases))
	for k, v := range s.cfg.Aliases {
		out[k] = v
	}
	return out, nil
}

// UpsertPluginEntry adds or updates a plugin entry in config.json.
func (s *Store) UpsertPluginEntry(entry types.InstalledPluginEntry) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i, p := range s.cfg.Plugins {
		if p.Package == entry.Package || p.Spec == entry.Spec {
			s.cfg.Plugins[i] = entry
			return s.saveConfigLocked()
		}
	}
	s.cfg.Plugins = append(s.cfg.Plugins, entry)
	return s.saveConfigLocked()
}

// RemovePluginEntry deletes a plugin entry from config.json.
func (s *Store) RemovePluginEntry(pkgOrSpec string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	filtered := s.cfg.Plugins[:0]
	for _, p := range s.cfg.Plugins {
		if p.Package == pkgOrSpec || p.Spec == pkgOrSpec {
			continue
		}
		filtered = append(filtered, p)
	}
	s.cfg.Plugins = filtered
	return s.saveConfigLocked()
}

// TogglePluginEntry sets enabled state on a plugin entry.
func (s *Store) TogglePluginEntry(pkgOrSpec string, enabled bool) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i, p := range s.cfg.Plugins {
		if p.Package == pkgOrSpec || p.Spec == pkgOrSpec {
			s.cfg.Plugins[i].Enabled = enabled
			return s.saveConfigLocked()
		}
	}
	return errors.New("plugin not installed")
}

// RecordRequest logs a completed gateway request, updates daily/monthly aggregates, and persists usage.json.
func (s *Store) RecordRequest(entry types.RequestLogEntry, redactHits map[string]int) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if entry.ID == "" {
		entry.ID = NewID("req")
	}
	if entry.Timestamp == "" {
		entry.Timestamp = types.NowRFC3339()
	}
	entry.IsLocal = entry.ClientKind == "loopback"
	entry.RedactionCount = entry.RedactedCount
	if len(entry.Attempts) > 1 {
		entry.FailoverAttempts = len(entry.Attempts) - 1
	}

	now := time.Now()
	day := now.Format("2006-01-02")
	month := now.Format("2006-01")

	b := s.usage.Daily[day]
	if b == nil {
		b = &types.DailyBucket{Date: day}
		s.usage.Daily[day] = b
	}
	b.Requests++
	if entry.StatusCode >= 200 && entry.StatusCode < 400 {
		b.SuccessRequests++
	} else {
		b.ErrorRequests++
	}
	b.InputTokens += entry.InputTokens
	b.OutputTokens += entry.OutputTokens
	b.EstimatedUsd += entry.EstimatedUsd
	if entry.TtftMs > 0 {
		b.TotalTtftMs += entry.TtftMs
		b.TtftCount++
	}
	b.RedactedCount += int64(entry.RedactedCount)

	if entry.KeyID != "" {
		kdKey := entry.KeyID + "|" + day
		kd := s.usage.KeyDaily[kdKey]
		if kd == nil {
			kd = &types.KeyUsageDay{Date: day}
			s.usage.KeyDaily[kdKey] = kd
		}
		kd.Requests++
		kd.EstimatedUsd += entry.EstimatedUsd
		s.usage.KeyMonthly[entry.KeyID+"|"+month] += entry.EstimatedUsd

		for i := range s.cfg.Keys {
			if s.cfg.Keys[i].ID == entry.KeyID {
				s.cfg.Keys[i].LastUsedAt = entry.Timestamp
				break
			}
		}
	}

	for kind, count := range redactHits {
		if count > 0 {
			s.usage.RedactByKind[kind] += int64(count)
			s.usage.RedactTotal += int64(count)
		}
	}

	// Prepend newest-first, cap at MaxLogEntries
	s.usage.Logs = append([]types.RequestLogEntry{entry}, s.usage.Logs...)
	if len(s.usage.Logs) > MaxLogEntries {
		s.usage.Logs = s.usage.Logs[:MaxLogEntries]
	}

	_ = s.saveUsageLocked()
}

// GetUsageSummary aggregates usage over "today", "7d", or "30d".
func (s *Store) GetUsageSummary(rng string) types.UsageSummary {
	s.mu.RLock()
	defer s.mu.RUnlock()

	days := 1
	switch rng {
	case "7d":
		days = 7
	case "30d":
		days = 30
	default:
		rng = "today"
	}

	now := time.Now()
	sum := types.UsageSummary{Range: rng}
	var ttftSum, ttftCount int64
	for i := 0; i < days; i++ {
		d := now.AddDate(0, 0, -i).Format("2006-01-02")
		b := s.usage.Daily[d]
		if b == nil {
			continue
		}
		sum.Requests += b.Requests
		sum.SuccessRequests += b.SuccessRequests
		sum.ErrorRequests += b.ErrorRequests
		sum.InputTokens += b.InputTokens
		sum.OutputTokens += b.OutputTokens
		sum.EstimatedUsd += b.EstimatedUsd
		sum.RedactedCount += b.RedactedCount
		ttftSum += b.TotalTtftMs
		ttftCount += b.TtftCount
	}
	sum.TotalTokens = sum.InputTokens + sum.OutputTokens
	if ttftCount > 0 {
		sum.AvgTtftMs = ttftSum / ttftCount
	}
	return sum
}

// GetLogs returns up to limit newest request log entries.
func (s *Store) GetLogs(limit int) []types.RequestLogEntry {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if limit <= 0 || limit > len(s.usage.Logs) {
		limit = len(s.usage.Logs)
	}
	out := make([]types.RequestLogEntry, limit)
	copy(out, s.usage.Logs[:limit])
	return out
}

// ClearLogs clears stored request log entries.
func (s *Store) ClearLogs() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.usage.Logs = []types.RequestLogEntry{}
	return s.saveUsageLocked()
}

// RedactSummary returns redaction settings summary and cumulative hit counts.
func (s *Store) RedactSummary() types.RedactSummary {
	s.mu.RLock()
	defer s.mu.RUnlock()
	hits := make(map[string]int64, len(s.usage.RedactByKind))
	for k, v := range s.usage.RedactByKind {
		hits[k] = v
	}
	return types.RedactSummary{
		Enabled:      s.cfg.Settings.RedactEnabled,
		Restore:      s.cfg.Settings.RedactRestore,
		RuleCount:    len(s.cfg.Settings.RedactRules),
		BuiltinRules: 7,
		CustomRules:  len(s.cfg.Settings.RedactRules),
		AllowCount:   len(s.cfg.Settings.RedactAllow),
		TotalHits:    s.usage.RedactTotal,
		HitsByKind:   hits,
	}
}

// ExportBackup builds a BackupBundle, optionally stripping secrets.
func (s *Store) ExportBackup(includeSecrets bool) types.BackupBundle {
	cfg := s.ConfigSnapshot()
	if !includeSecrets {
		for i := range cfg.Keys {
			cfg.Keys[i].Secret = ""
		}
		for i := range cfg.Providers {
			for j := range cfg.Providers[i].Keys {
				cfg.Providers[i].Keys[j].Secret = ""
			}
		}
	}
	return types.BackupBundle{
		Version:        1,
		ExportedAt:     types.NowRFC3339(),
		IncludeSecrets: includeSecrets,
		Config:         cfg,
	}
}

// ImportBackup restores configuration from a BackupBundle.
func (s *Store) ImportBackup(bundle types.BackupBundle) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	cfg := cloneConfig(bundle.Config)
	// Preserve existing secrets if backup omitted them for matching IDs.
	if !bundle.IncludeSecrets {
		oldKeySecrets := make(map[string]string, len(s.cfg.Keys))
		for _, k := range s.cfg.Keys {
			oldKeySecrets[k.ID] = k.Secret
		}
		for i := range cfg.Keys {
			if cfg.Keys[i].Secret == "" {
				if sec := oldKeySecrets[cfg.Keys[i].ID]; sec != "" {
					cfg.Keys[i].Secret = sec
				} else {
					cfg.Keys[i].Secret = NewGatewaySecret()
				}
			}
		}
		oldProvSecrets := make(map[string]map[string]string)
		for _, p := range s.cfg.Providers {
			m := make(map[string]string)
			for _, pk := range p.Keys {
				m[pk.ID] = pk.Secret
			}
			oldProvSecrets[p.ID] = m
		}
		for i := range cfg.Providers {
			pm := oldProvSecrets[cfg.Providers[i].ID]
			for j := range cfg.Providers[i].Keys {
				if cfg.Providers[i].Keys[j].Secret == "" && pm != nil {
					cfg.Providers[i].Keys[j].Secret = pm[cfg.Providers[i].Keys[j].ID]
				}
			}
		}
	}
	normalizeConfig(&cfg)
	s.cfg = cfg
	return s.saveConfigLocked()
}
