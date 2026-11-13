package plugin

import "github.com/falcon-gateway/falcon/core/internal/types"

// PluginModelInfo describes a model exposed by a plugin provider.
type PluginModelInfo struct {
	ID       string         `json:"id"`
	Name     string         `json:"name"`
	Npm      string         `json:"npm,omitempty"`
	Protocol types.Protocol `json:"protocol"`
	URL      string         `json:"url,omitempty"`
	APIID    string         `json:"apiId,omitempty"`
	Context  int            `json:"context,omitempty"`
	Output   int            `json:"output,omitempty"`
	Free     bool           `json:"free,omitempty"`
}

// PluginAuthMethod describes one sign-in method exposed by a plugin.
type PluginAuthMethod struct {
	Index       int    `json:"index"`
	Type        string `json:"type"` // "api" | "oauth"
	Label       string `json:"label"`
	Keyless     bool   `json:"keyless,omitempty"`
	Placeholder string `json:"placeholder,omitempty"`
}

// PluginOption describes a toggleable plugin provider option.
type PluginOption struct {
	Key           string `json:"key"`
	Label         string `json:"label"`
	LabelEn       string `json:"labelEn,omitempty"`
	Description   string `json:"description,omitempty"`
	DescriptionEn string `json:"descriptionEn,omitempty"`
	Value         bool   `json:"value"`
	FiltersModels bool   `json:"filtersModels,omitempty"`
}

// QuotaWindow represents one quota window returned by a plugin's usage hook.
type QuotaWindow struct {
	Name         string   `json:"name"`
	Label        string   `json:"label,omitempty"`
	Used         *float64 `json:"used,omitempty"`
	Display      string   `json:"display,omitempty"`
	ResetsAt     string   `json:"resetsAt,omitempty"`
	ResetAt      string   `json:"resetAt,omitempty"`
	ResetSecs    int64    `json:"resetSecs,omitempty"`
	Amount       float64  `json:"amount,omitempty"`
	Limit        float64  `json:"limit,omitempty"`
	RemainingPct *float64 `json:"remainingPct,omitempty"`
	Unit         string   `json:"unit,omitempty"`
	Balance      *float64 `json:"balance,omitempty"`
}

// PluginUsage holds account quota usage details.
type PluginUsage struct {
	Plan    string        `json:"plan,omitempty"`
	User    string        `json:"user,omitempty"`
	Balance string        `json:"balance,omitempty"`
	Until   string        `json:"until,omitempty"`
	Error   string        `json:"error,omitempty"`
	Windows []QuotaWindow `json:"windows,omitempty"`
}

// PluginCheckinResult records the outcome of an account's daily check-in.
type PluginCheckinResult struct {
	Outcome string  `json:"outcome"`
	Credit  float64 `json:"credit,omitempty"`
	Streak  int     `json:"streak,omitempty"`
	Message string  `json:"message,omitempty"`
	At      string  `json:"at,omitempty"`
}

// PluginAccountState represents one signed-in plugin account.
type PluginAccountState struct {
	ID          string               `json:"id"`
	ProviderID  string               `json:"providerId"`
	Type        string               `json:"type"` // "api" | "oauth"
	Label       string               `json:"label"`
	Email       string               `json:"email,omitempty"`
	Status      string               `json:"status"` // "active" | "expired" | "error"
	Enabled     bool                 `json:"enabled"`
	Quota       *PluginUsage         `json:"quota,omitempty"`
	Quotas      []QuotaWindow        `json:"quotas,omitempty"`
	LastCheckin *PluginCheckinResult `json:"lastCheckin,omitempty"`
}

// PluginProviderState represents one provider registered by an installed plugin.
type PluginProviderState struct {
	ID              string               `json:"id"`
	Name            string               `json:"name"`
	Protocol        types.Protocol       `json:"protocol"`
	Models          []PluginModelInfo    `json:"models"`
	Methods         []PluginAuthMethod   `json:"methods"`
	Options         []PluginOption       `json:"options"`
	SupportsUsage   bool                 `json:"supportsUsage"`
	SupportsCheckin bool                 `json:"supportsCheckin"`
	Accounts        []PluginAccountState `json:"accounts"`
	ListError       string               `json:"listError,omitempty"`
}

// InstalledPluginState is returned in GET /admin/v1/state -> plugins.
type InstalledPluginState struct {
	Package     string                `json:"package"`
	ID          string                `json:"id"`
	Name        string                `json:"name"`
	Installed   bool                  `json:"installed"`
	Enabled     bool                  `json:"enabled"`
	Version     string                `json:"version,omitempty"`
	Error       string                `json:"error,omitempty"`
	ProviderIDs []string              `json:"providers"`
	Models      []string              `json:"models"`
	Options     map[string]any        `json:"options"`
	Accounts    []PluginAccountState  `json:"accounts"`
	Providers   []PluginProviderState `json:"providerDetails,omitempty"`
}

// SignInStartRequest initiates a plugin account sign-in.
type SignInStartRequest struct {
	Package     string            `json:"package,omitempty"`
	ProviderID  string            `json:"providerId"`
	MethodIndex int               `json:"methodIndex"`
	APIKey      string            `json:"apiKey,omitempty"`
	Account     string            `json:"account,omitempty"`
	Inputs      map[string]string `json:"inputs,omitempty"`
}

// SignInSessionState represents the live status of a sign-in flow.
type SignInSessionState struct {
	SessionID    string              `json:"sessionId"`
	ProviderID   string              `json:"providerId"`
	Status       string              `json:"status"` // "pending" | "completed" | "failed"
	Phase        string              `json:"phase"`  // "starting" | "open" | "device" | "prompt" | "done" | "failed"
	Method       string              `json:"method,omitempty"` // "api" | "auto" | "code"
	URL          string              `json:"url,omitempty"`
	Instructions string              `json:"instructions,omitempty"`
	PromptLabel  string              `json:"promptLabel,omitempty"`
	DeviceCode   string              `json:"deviceCode,omitempty"`
	UserCode     string              `json:"userCode,omitempty"`
	AccountID    string              `json:"accountId,omitempty"`
	Account      *PluginAccountState `json:"account,omitempty"`
	Error        string              `json:"error,omitempty"`
}

// AuthRecord is the persisted JSON shape in plugin-auth.json (OpenCode compatible).
type AuthRecord struct {
	Type     string            `json:"type"` // "api" | "oauth"
	Key      string            `json:"key,omitempty"`
	Refresh  string            `json:"refresh,omitempty"`
	Access   string            `json:"access,omitempty"`
	Expires  int64             `json:"expires,omitempty"`
	Email    string            `json:"email,omitempty"`
	Metadata map[string]string `json:"metadata,omitempty"`
}
