package types

import (
	"encoding/json"
	"time"
)

// Protocol identifies an API dialect spoken by Falcon or an upstream provider.
type Protocol string

const (
	ProtocolOpenAI    Protocol = "openai"
	ProtocolResponses Protocol = "responses"
	ProtocolAnthropic Protocol = "anthropic"
	ProtocolGemini    Protocol = "gemini"
	ProtocolOllama    Protocol = "ollama"
)

// Settings holds persisted gateway configuration.
type Settings struct {
	Port              int          `json:"port"`
	LanEnabled        bool         `json:"lanEnabled"`
	AllowLocalKeyless bool         `json:"allowLocalKeyless"`
	AllowIps          []string     `json:"allowIps"`
	CorsOrigins       []string     `json:"corsOrigins"`
	RedactEnabled     bool         `json:"redactEnabled"`
	RedactRestore     bool         `json:"redactRestore"`
	RedactRules       []RedactRule `json:"redactRules"`
	RedactAllow       []string     `json:"redactAllow"`
	ChinaMirror       bool         `json:"chinaMirror"`
}

// DefaultSettings returns initial gateway defaults.
func DefaultSettings() Settings {
	return Settings{
		Port:              18787,
		LanEnabled:        false,
		AllowLocalKeyless: true,
		AllowIps:          []string{},
		CorsOrigins:       []string{},
		RedactEnabled:     false,
		RedactRestore:     true,
		RedactRules:       []RedactRule{},
		RedactAllow:       []string{},
		ChinaMirror:       true,
	}
}

// SettingsPatch represents partial updates to Settings.
type SettingsPatch struct {
	Port              *int          `json:"port,omitempty"`
	LanEnabled        *bool         `json:"lanEnabled,omitempty"`
	AllowLocalKeyless *bool         `json:"allowLocalKeyless,omitempty"`
	AllowIps          *[]string     `json:"allowIps,omitempty"`
	CorsOrigins       *[]string     `json:"corsOrigins,omitempty"`
	RedactEnabled     *bool         `json:"redactEnabled,omitempty"`
	RedactRestore     *bool         `json:"redactRestore,omitempty"`
	RedactRules       *[]RedactRule `json:"redactRules,omitempty"`
	RedactAllow       *[]string     `json:"redactAllow,omitempty"`
	ChinaMirror       *bool         `json:"chinaMirror,omitempty"`
}

// RedactRule is a user-defined regex redaction rule.
type RedactRule struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Pattern     string `json:"pattern"`
	Placeholder string `json:"placeholder,omitempty"`
	Replacement string `json:"replacement,omitempty"`
	Enabled     bool   `json:"enabled"`
}

// AccessKey is a named gateway API key (sk-flc-...).
type AccessKey struct {
	ID              string   `json:"id"`
	Name            string   `json:"name"`
	Enabled         bool     `json:"enabled"`
	Secret          string   `json:"secret,omitempty"`
	Masked          string   `json:"masked,omitempty"`
	Prefix          string   `json:"prefix,omitempty"`
	AllowedModels   []string `json:"allowedModels"`
	DailyLimitUsd   float64  `json:"dailyLimitUsd"`
	MonthlyLimitUsd float64  `json:"monthlyLimitUsd"`
	DailyLimitReqs  int64    `json:"dailyLimitReqs"`
	CreatedAt       string   `json:"createdAt"`
	LastUsedAt      string   `json:"lastUsedAt,omitempty"`
	TodayReqs       int64    `json:"todayReqs,omitempty"`
	TodayUsd        float64  `json:"todayUsd,omitempty"`
	MonthUsd        float64  `json:"monthUsd,omitempty"`
}

// ProviderKey is one upstream API key in a provider's key pool.
type ProviderKey struct {
	ID           string `json:"id"`
	Label        string `json:"label"`
	Secret       string `json:"secret,omitempty"`
	Masked       string `json:"masked,omitempty"`
	MaskedSecret string `json:"maskedSecret,omitempty"`
	Enabled      bool   `json:"enabled"`
	Weight       int    `json:"weight"`
}

// ProviderTestResult stores the outcome of a live 1-token connectivity probe.
type ProviderTestResult struct {
	Ok           bool   `json:"ok"`
	StatusCode   int    `json:"statusCode"`
	LatencyMs    int64  `json:"latencyMs"`
	Model        string `json:"model"`
	ReplyPreview string `json:"replyPreview,omitempty"`
	Error        string `json:"error,omitempty"`
	TestedAt     string `json:"testedAt"`
}

// Provider is a configured upstream API provider.
type Provider struct {
	ID              string              `json:"id"`
	Name            string              `json:"name"`
	Preset          string              `json:"preset"`
	Protocol        Protocol            `json:"protocol"`
	BaseURL         string              `json:"baseUrl"`
	Enabled         bool                `json:"enabled"`
	Keys            []ProviderKey       `json:"keys"`
	Models          []string            `json:"models"`
	SelectedModels  []string            `json:"selectedModels"`
	AvailableModels []string            `json:"availableModels,omitempty"`
	LastTest        *ProviderTestResult `json:"lastTest,omitempty"`
}

// ActiveModels returns SelectedModels when explicitly configured (non-nil),
// falling back to Models for legacy/simple provider configs.
func (p Provider) ActiveModels() []string {
	if p.SelectedModels != nil {
		return p.SelectedModels
	}
	return p.Models
}

// ProviderPreset describes a built-in provider template.
type ProviderPreset struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	NameZh      string   `json:"nameZh"`
	Protocol    Protocol `json:"protocol"`
	BaseURL     string   `json:"baseUrl"`
	Models      []string `json:"models"`
	RequiresKey bool     `json:"requiresKey"`
	Hint        string   `json:"hint,omitempty"`
}

// RoutingStrategy defines how a routing group selects targets.
type RoutingStrategy string

const (
	StrategyOrder      RoutingStrategy = "order"
	StrategyRoundRobin RoutingStrategy = "round_robin"
	StrategyFastest    RoutingStrategy = "fastest"
	StrategyManual     RoutingStrategy = "manual"
)

// RoutingGroup groups multiple "<provider>/<model>" targets with failover.
type RoutingGroup struct {
	ID           string          `json:"id"`
	Name         string          `json:"name"`
	Strategy     RoutingStrategy `json:"strategy"`
	PinnedTarget string          `json:"pinnedTarget,omitempty"`
	Targets      []string        `json:"targets"`
	Enabled      bool            `json:"enabled"`
}

type routingGroupJSON struct {
	ID           string          `json:"id"`
	Name         string          `json:"name"`
	Strategy     RoutingStrategy `json:"strategy"`
	PinnedTarget string          `json:"pinnedTarget,omitempty"`
	PinnedMember string          `json:"pinnedMember,omitempty"`
	Targets      []string        `json:"targets"`
	Members      []string        `json:"members"`
	Enabled      bool            `json:"enabled"`
}

func (g RoutingGroup) MarshalJSON() ([]byte, error) {
	targets := g.Targets
	if targets == nil {
		targets = []string{}
	}
	return json.Marshal(routingGroupJSON{
		ID:           g.ID,
		Name:         g.Name,
		Strategy:     g.Strategy,
		PinnedTarget: g.PinnedTarget,
		PinnedMember: g.PinnedTarget,
		Targets:      targets,
		Members:      targets,
		Enabled:      g.Enabled,
	})
}

func (g *RoutingGroup) UnmarshalJSON(data []byte) error {
	var raw routingGroupJSON
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	g.ID = raw.ID
	g.Name = raw.Name
	g.Strategy = raw.Strategy
	g.Enabled = raw.Enabled
	g.PinnedTarget = raw.PinnedTarget
	if g.PinnedTarget == "" {
		g.PinnedTarget = raw.PinnedMember
	}
	if len(raw.Targets) > 0 {
		g.Targets = raw.Targets
	} else if raw.Members != nil {
		g.Targets = raw.Members
	} else {
		g.Targets = []string{}
	}
	return nil
}

// InstalledPluginEntry is persisted in config.json for plugin management.
type InstalledPluginEntry struct {
	Package string `json:"package"`
	Spec    string `json:"spec"`
	Enabled bool   `json:"enabled"`
}

// Config is the root configuration persisted to config.json.
type Config struct {
	Version   int                    `json:"version"`
	Settings  Settings               `json:"settings"`
	Keys      []AccessKey            `json:"keys"`
	Providers []Provider             `json:"providers"`
	Groups    []RoutingGroup         `json:"groups"`
	Aliases   map[string]string      `json:"aliases"`
	Plugins   []InstalledPluginEntry `json:"plugins"`
}

// DefaultConfig returns a fresh configuration.
func DefaultConfig() Config {
	return Config{
		Version:   1,
		Settings:  DefaultSettings(),
		Keys:      []AccessKey{},
		Providers: []Provider{},
		Groups:    []RoutingGroup{},
		Aliases:   map[string]string{},
		Plugins:   []InstalledPluginEntry{},
	}
}

// AttemptLog records one upstream attempt during routing/failover.
type AttemptLog struct {
	Target     string `json:"target"`
	StatusCode int    `json:"statusCode"`
	LatencyMs  int64  `json:"latencyMs"`
	Error      string `json:"error,omitempty"`
}

// RequestLogEntry records one gateway request (capped at 500 entries).
type RequestLogEntry struct {
	ID               string       `json:"id"`
	Timestamp        string       `json:"timestamp"`
	ClientIP         string       `json:"clientIp"`
	ClientKind       string       `json:"clientKind"` // "loopback" | "lan"
	IsLocal          bool         `json:"isLocal"`
	KeyID            string       `json:"keyId"`
	KeyName          string       `json:"keyName"`
	Protocol         Protocol     `json:"protocol"`
	Path             string       `json:"path"`
	RequestedModel   string       `json:"requestedModel"`
	UpstreamProvider string       `json:"upstreamProvider"`
	UpstreamModel    string       `json:"upstreamModel"`
	StatusCode       int          `json:"statusCode"`
	TtftMs           int64        `json:"ttftMs"`
	LatencyMs        int64        `json:"latencyMs"`
	InputTokens      int64        `json:"inputTokens"`
	OutputTokens     int64        `json:"outputTokens"`
	EstimatedUsd     float64      `json:"estimatedUsd"`
	FailoverAttempts int          `json:"failoverAttempts"`
	RedactedCount    int          `json:"redactedCount"`
	RedactionCount   int          `json:"redactionCount"`
	Attempts         []AttemptLog `json:"attempts,omitempty"`
	Error            string       `json:"error,omitempty"`
}

// DailyBucket aggregates usage for one YYYY-MM-DD day.
type DailyBucket struct {
	Date            string  `json:"date"`
	Requests        int64   `json:"requests"`
	SuccessRequests int64   `json:"successRequests"`
	ErrorRequests   int64   `json:"errorRequests"`
	InputTokens     int64   `json:"inputTokens"`
	OutputTokens    int64   `json:"outputTokens"`
	EstimatedUsd    float64 `json:"estimatedUsd"`
	TotalTtftMs     int64   `json:"totalTtftMs"`
	TtftCount       int64   `json:"ttftCount"`
	RedactedCount   int64   `json:"redactedCount"`
}

// KeyUsageDay tracks per-key daily consumption.
type KeyUsageDay struct {
	Date         string  `json:"date"`
	Requests     int64   `json:"requests"`
	EstimatedUsd float64 `json:"estimatedUsd"`
}

// UsageStore is persisted to usage.json.
type UsageStore struct {
	Version      int                       `json:"version"`
	Daily        map[string]*DailyBucket   `json:"daily"`
	KeyDaily     map[string]*KeyUsageDay   `json:"keyDaily"`     // "<keyId>|<YYYY-MM-DD>"
	KeyMonthly   map[string]float64        `json:"keyMonthly"`   // "<keyId>|<YYYY-MM>" -> usd
	RedactByKind map[string]int64          `json:"redactByKind"` // kind -> total hits
	RedactTotal  int64                     `json:"redactTotal"`
	Logs         []RequestLogEntry         `json:"logs"`
}

// NewUsageStore returns an empty UsageStore.
func NewUsageStore() UsageStore {
	return UsageStore{
		Version:      1,
		Daily:        map[string]*DailyBucket{},
		KeyDaily:     map[string]*KeyUsageDay{},
		KeyMonthly:   map[string]float64{},
		RedactByKind: map[string]int64{},
		Logs:         []RequestLogEntry{},
	}
}

// UsageSummary is returned by /admin/v1/state and /admin/v1/usage.
type UsageSummary struct {
	Range           string  `json:"range"`
	Requests        int64   `json:"requests"`
	SuccessRequests int64   `json:"successRequests"`
	ErrorRequests   int64   `json:"errorRequests"`
	InputTokens     int64   `json:"inputTokens"`
	OutputTokens    int64   `json:"outputTokens"`
	TotalTokens     int64   `json:"totalTokens"`
	EstimatedUsd    float64 `json:"estimatedUsd"`
	AvgTtftMs       int64   `json:"avgTtftMs"`
	RedactedCount   int64   `json:"redactedCount"`
}

// RedactSummary summarizes redaction status and cumulative hits.
type RedactSummary struct {
	Enabled      bool             `json:"enabled"`
	Restore      bool             `json:"restore"`
	RuleCount    int              `json:"ruleCount"`
	BuiltinRules int              `json:"builtinRules"`
	CustomRules  int              `json:"customRules"`
	AllowCount   int              `json:"allowCount"`
	TotalHits    int64            `json:"totalHits"`
	HitsByKind   map[string]int64 `json:"hitsByKind"`
}

// GatewayStatus describes the runtime status of the gateway listener.
type GatewayStatus struct {
	Running             bool     `json:"running"`
	ListenAddr          string   `json:"listenAddr"`
	Port                int      `json:"port"`
	LanEnabled          bool     `json:"lanEnabled"`
	AllowLocalKeyless   bool     `json:"allowLocalKeyless"`
	LanUrls             []string `json:"lanUrls"`
	LoopbackUrl         string   `json:"loopbackUrl"`
	UptimeSec           int64    `json:"uptimeSec"`
	ModelCount          int      `json:"modelCount"`
	ActiveProviderCount int      `json:"activeProviderCount"`
	PluginRuntimeMode   string   `json:"pluginRuntimeMode"`
}

// BackupBundle is exported/imported via /admin/v1/backup/*.
type BackupBundle struct {
	Version        int       `json:"version"`
	ExportedAt     string    `json:"exportedAt"`
	IncludeSecrets bool      `json:"includeSecrets"`
	Config         Config    `json:"config"`
}

// MaskSecret obscures a secret while keeping a short prefix and suffix.
func MaskSecret(s string) string {
	if s == "" {
		return ""
	}
	if len(s) <= 8 {
		return "****"
	}
	if len(s) <= 14 {
		return s[:4] + "..." + s[len(s)-2:]
	}
	return s[:8] + "..." + s[len(s)-4:]
}

// NowRFC3339 returns UTC RFC3339 timestamp.
func NowRFC3339() string {
	return time.Now().UTC().Format(time.RFC3339)
}
