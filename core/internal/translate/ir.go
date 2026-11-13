package translate

import (
	"encoding/json"

	"github.com/falcon-gateway/falcon/core/internal/types"
)

// ContentPart represents one part of a message (text, image, tool_use, tool_result, thinking).
type ContentPart struct {
	Type       string         `json:"type"` // "text", "image", "tool_use", "tool_result", "thinking"
	Text       string         `json:"text,omitempty"`
	ImageURL   string         `json:"imageUrl,omitempty"`
	MediaType  string         `json:"mediaType,omitempty"`
	ImageData  string         `json:"imageData,omitempty"`
	ToolID     string         `json:"toolId,omitempty"`
	ToolName   string         `json:"toolName,omitempty"`
	ToolInput  any            `json:"toolInput,omitempty"`
	ToolOutput string         `json:"toolOutput,omitempty"`
	IsError    bool           `json:"isError,omitempty"`
}

// Message is one conversation turn in canonical form.
type Message struct {
	Role       string        `json:"role"` // "system", "user", "assistant", "tool"
	Parts      []ContentPart `json:"parts"`
	ToolCallID string        `json:"toolCallId,omitempty"`
	Name       string        `json:"name,omitempty"`
}

// ToolDef is a function tool definition in canonical form.
type ToolDef struct {
	Name        string         `json:"name"`
	Description string         `json:"description,omitempty"`
	Parameters  map[string]any `json:"parameters,omitempty"`
}

// CanonicalRequest is the protocol-neutral request IR.
type CanonicalRequest struct {
	Model         string    `json:"model"`
	System        string    `json:"system,omitempty"`
	Messages      []Message `json:"messages"`
	Tools         []ToolDef `json:"tools,omitempty"`
	ToolChoice    any       `json:"toolChoice,omitempty"`
	Stream        bool      `json:"stream"`
	MaxTokens     int       `json:"maxTokens,omitempty"`
	Temperature   *float64  `json:"temperature,omitempty"`
	TopP          *float64  `json:"topP,omitempty"`
	Stop          []string  `json:"stop,omitempty"`
}

// Usage holds token counts in canonical form.
type Usage struct {
	InputTokens  int64 `json:"inputTokens"`
	OutputTokens int64 `json:"outputTokens"`
	TotalTokens  int64 `json:"totalTokens"`
}

// CanonicalResponse is the protocol-neutral non-streaming response IR.
type CanonicalResponse struct {
	ID           string        `json:"id"`
	Model        string        `json:"model"`
	Parts        []ContentPart `json:"parts"`
	FinishReason string        `json:"finishReason"` // "stop", "tool_calls", "length"
	Usage        Usage         `json:"usage"`
}

// StreamEventKind identifies a canonical streaming event.
type StreamEventKind string

const (
	EventStart         StreamEventKind = "start"
	EventTextDelta     StreamEventKind = "text_delta"
	EventThinkingDelta StreamEventKind = "thinking_delta"
	EventToolStart     StreamEventKind = "tool_start"
	EventToolDelta     StreamEventKind = "tool_delta"
	EventFinish        StreamEventKind = "finish"
)

// StreamEvent is a protocol-neutral streaming event.
type StreamEvent struct {
	Kind         StreamEventKind
	ID           string
	Model        string
	Text         string
	ToolIndex    int
	ToolID       string
	ToolName     string
	ToolArgs     string
	FinishReason string
	Usage        *Usage
}

// RewriteModelJSON updates only the "model" field in a raw JSON payload while keeping all other fields intact.
func RewriteModelJSON(raw []byte, newModel string) []byte {
	if newModel == "" || len(raw) == 0 {
		return raw
	}
	var m map[string]any
	if err := json.Unmarshal(raw, &m); err != nil {
		return raw
	}
	if _, hasModel := m["model"]; hasModel || len(m) > 0 {
		m["model"] = newModel
	}
	out, err := json.Marshal(m)
	if err != nil {
		return raw
	}
	return out
}

// UpstreamPath returns the relative upstream endpoint path for a target protocol.
func UpstreamPath(proto types.Protocol, model string, stream bool) string {
	switch proto {
	case types.ProtocolOpenAI:
		return "/chat/completions"
	case types.ProtocolResponses:
		return "/responses"
	case types.ProtocolAnthropic:
		return "/messages"
	case types.ProtocolGemini:
		action := "generateContent"
		if stream {
			action = "streamGenerateContent?alt=sse"
		}
		return "/models/" + model + ":" + action
	case types.ProtocolOllama:
		return "/api/chat"
	default:
		return "/chat/completions"
	}
}

func asString(v any) string {
	if s, ok := v.(string); ok {
		return s
	}
	return ""
}

func asInt(v any) int {
	switch n := v.(type) {
	case float64:
		return int(n)
	case int:
		return n
	case int64:
		return int(n)
	default:
		return 0
	}
}

func asInt64(v any) int64 {
	switch n := v.(type) {
	case float64:
		return int64(n)
	case int64:
		return n
	case int:
		return int64(n)
	default:
		return 0
	}
}

func asFloatPtr(v any) *float64 {
	if f, ok := v.(float64); ok {
		return &f
	}
	return nil
}

func normalizeFinishReason(r string) string {
	switch r {
	case "tool_use", "tool_calls", "function_call":
		return "tool_calls"
	case "max_tokens", "length", "MAX_TOKENS":
		return "length"
	default:
		return "stop"
	}
}
