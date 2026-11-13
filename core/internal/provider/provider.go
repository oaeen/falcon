package provider

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/rand/v2"
	"net/http"
	"strings"
	"time"

	"github.com/falcon-gateway/falcon/core/internal/translate"
	"github.com/falcon-gateway/falcon/core/internal/types"
)

// Presets returns the built-in 15+ provider templates.
func Presets() []types.ProviderPreset {
	list := []types.ProviderPreset{
		{
			ID: "openai", Name: "OpenAI", NameZh: "OpenAI",
			Protocol: types.ProtocolOpenAI, BaseURL: "https://api.openai.com/v1",
			Models: []string{"gpt-4o", "gpt-4o-mini", "gpt-4.1", "o3-mini"},
		},
		{
			ID: "anthropic", Name: "Anthropic", NameZh: "Anthropic",
			Protocol: types.ProtocolAnthropic, BaseURL: "https://api.anthropic.com/v1",
			Models: []string{"claude-sonnet-4-5", "claude-3-7-sonnet-latest", "claude-3-5-haiku-latest"},
		},
		{
			ID: "gemini", Name: "Google Gemini", NameZh: "Google Gemini",
			Protocol: types.ProtocolGemini, BaseURL: "https://generativelanguage.googleapis.com/v1beta",
			Models: []string{"gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash"},
		},
		{
			ID: "deepseek", Name: "DeepSeek", NameZh: "DeepSeek 深度求索",
			Protocol: types.ProtocolOpenAI, BaseURL: "https://api.deepseek.com/v1",
			Models: []string{"deepseek-chat", "deepseek-reasoner"},
		},
		{
			ID: "openrouter", Name: "OpenRouter", NameZh: "OpenRouter",
			Protocol: types.ProtocolOpenAI, BaseURL: "https://openrouter.ai/api/v1",
			Models: []string{"openai/gpt-4o-mini", "anthropic/claude-sonnet-4", "google/gemini-2.5-flash"},
		},
		{
			ID: "siliconflow", Name: "SiliconFlow", NameZh: "硅基流动 SiliconFlow",
			Protocol: types.ProtocolOpenAI, BaseURL: "https://api.siliconflow.cn/v1",
			Models: []string{"Qwen/Qwen2.5-72B-Instruct", "deepseek-ai/DeepSeek-V3", "deepseek-ai/DeepSeek-R1"},
		},
		{
			ID: "moonshot", Name: "Moonshot Kimi", NameZh: "月之暗面 Kimi",
			Protocol: types.ProtocolOpenAI, BaseURL: "https://api.moonshot.cn/v1",
			Models: []string{"kimi-k2-0711-preview", "moonshot-v1-8k", "moonshot-v1-32k"},
		},
		{
			ID: "zhipu", Name: "Zhipu GLM", NameZh: "智谱清言 GLM",
			Protocol: types.ProtocolOpenAI, BaseURL: "https://open.bigmodel.cn/api/paas/v4",
			Models: []string{"glm-4-plus", "glm-4-air", "glm-4-flash"},
		},
		{
			ID: "dashscope", Name: "Alibaba DashScope", NameZh: "阿里云百炼 DashScope",
			Protocol: types.ProtocolOpenAI, BaseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
			Models: []string{"qwen-max", "qwen-plus", "qwen-turbo", "qwq-plus"},
		},
		{
			ID: "minimax", Name: "MiniMax", NameZh: "MiniMax 稀宇",
			Protocol: types.ProtocolOpenAI, BaseURL: "https://api.minimaxi.com/v1",
			Models: []string{"MiniMax-Text-01", "abab6.5s-chat"},
		},
		{
			ID: "volcengine", Name: "Volcengine Ark", NameZh: "火山方舟 Volcengine",
			Protocol: types.ProtocolOpenAI, BaseURL: "https://ark.cn-beijing.volces.com/api/v3",
			Models: []string{"doubao-1.5-pro-32k", "doubao-1.5-lite-32k"},
		},
		{
			ID: "groq", Name: "Groq", NameZh: "Groq",
			Protocol: types.ProtocolOpenAI, BaseURL: "https://api.groq.com/openai/v1",
			Models: []string{"llama-3.3-70b-versatile", "llama-3.1-8b-instant", "mixtral-8x7b-32768"},
		},
		{
			ID: "xai", Name: "xAI Grok", NameZh: "xAI Grok",
			Protocol: types.ProtocolOpenAI, BaseURL: "https://api.x.ai/v1",
			Models: []string{"grok-3", "grok-3-mini"},
		},
		{
			ID: "ollama", Name: "Ollama", NameZh: "Ollama 本地模型",
			Protocol: types.ProtocolOllama, BaseURL: "http://127.0.0.1:11434",
			Models: []string{"llama3.2", "qwen2.5:7b"},
		},
		{
			ID: "custom", Name: "Custom Provider", NameZh: "自定义渠道",
			Protocol: types.ProtocolOpenAI, BaseURL: "",
			Models: []string{},
		},
	}
	for i := range list {
		list[i].RequiresKey = list[i].Protocol != types.ProtocolOllama
	}
	return list
}

// FindPreset returns a preset by ID.
func FindPreset(id string) (types.ProviderPreset, bool) {
	for _, p := range Presets() {
		if p.ID == id {
			return p, true
		}
	}
	return types.ProviderPreset{}, false
}

// PickKey selects an enabled key from p using weighted random selection, excluding any key IDs in skip.
func PickKey(p types.Provider, skip map[string]bool) (types.ProviderKey, bool) {
	var candidates []types.ProviderKey
	totalWeight := 0
	for _, k := range p.Keys {
		if !k.Enabled || strings.TrimSpace(k.Secret) == "" {
			continue
		}
		if skip != nil && skip[k.ID] {
			continue
		}
		w := k.Weight
		if w <= 0 {
			w = 1
		}
		candidates = append(candidates, k)
		totalWeight += w
	}
	if len(candidates) == 0 {
		return types.ProviderKey{}, false
	}
	if totalWeight <= 0 || len(candidates) == 1 {
		return candidates[0], true
	}
	r := rand.IntN(totalWeight)
	for _, c := range candidates {
		w := c.Weight
		if w <= 0 {
			w = 1
		}
		if r < w {
			return c, true
		}
		r -= w
	}
	return candidates[0], true
}

// ApplyUpstreamAuth sets provider-protocol authentication headers on an outgoing http.Request.
func ApplyUpstreamAuth(req *http.Request, proto types.Protocol, secret string) {
	if strings.TrimSpace(secret) == "" {
		return
	}
	switch proto {
	case types.ProtocolAnthropic:
		req.Header.Set("x-api-key", secret)
		if req.Header.Get("anthropic-version") == "" {
			req.Header.Set("anthropic-version", "2023-06-01")
		}
	case types.ProtocolGemini:
		req.Header.Set("x-goog-api-key", secret)
	default:
		req.Header.Set("Authorization", "Bearer "+secret)
	}
}

// BuildUpstreamURL joins baseURL and relative path cleanly without duplicate /v1 segments.
func BuildUpstreamURL(baseURL string, relPath string) string {
	base := strings.TrimRight(strings.TrimSpace(baseURL), "/")
	if base == "" {
		return relPath
	}
	if !strings.HasPrefix(relPath, "/") {
		relPath = "/" + relPath
	}
	if strings.HasSuffix(base, "/v1") && strings.HasPrefix(relPath, "/v1/") {
		relPath = strings.TrimPrefix(relPath, "/v1")
	}
	return base + relPath
}

// FetchModels queries the upstream provider's models listing endpoint.
func FetchModels(ctx context.Context, client *http.Client, p types.Provider) ([]string, error) {
	if client == nil {
		client = &http.Client{Timeout: 15 * time.Second}
	}
	base := strings.TrimRight(strings.TrimSpace(p.BaseURL), "/")
	if base == "" {
		if preset, ok := FindPreset(p.Preset); ok && preset.BaseURL != "" {
			base = preset.BaseURL
		}
	}
	if base == "" {
		return nil, errors.New("provider baseUrl is empty")
	}

	var endpoint string
	switch p.Protocol {
	case types.ProtocolOllama:
		endpoint = BuildUpstreamURL(base, "/api/tags")
	case types.ProtocolGemini:
		endpoint = BuildUpstreamURL(base, "/models")
	default:
		endpoint = BuildUpstreamURL(base, "/models")
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, err
	}
	if key, ok := PickKey(p, nil); ok {
		ApplyUpstreamAuth(req, p.Protocol, key.Secret)
	}

	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return nil, err
	}
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("upstream HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}

	var parsed map[string]any
	if err := json.Unmarshal(body, &parsed); err != nil {
		return nil, fmt.Errorf("parse models response: %w", err)
	}

	var models []string
	seen := make(map[string]struct{})
	addModel := func(id string) {
		id = strings.TrimSpace(id)
		id = strings.TrimPrefix(id, "models/")
		if id == "" {
			return
		}
		if _, exists := seen[id]; !exists {
			seen[id] = struct{}{}
			models = append(models, id)
		}
	}

	if data, ok := parsed["data"].([]any); ok {
		for _, item := range data {
			if m, ok := item.(map[string]any); ok {
				if id, ok := m["id"].(string); ok {
					addModel(id)
				}
			}
		}
	}
	if gms, ok := parsed["models"].([]any); ok {
		for _, item := range gms {
			if m, ok := item.(map[string]any); ok {
				if name, ok := m["name"].(string); ok {
					addModel(name)
				} else if model, ok := m["model"].(string); ok {
					addModel(model)
				}
			}
		}
	}
	if len(models) == 0 {
		return nil, errors.New("no models found in upstream response")
	}
	return models, nil
}

// TestConnectivity sends a minimal 1-token chat request to verify connectivity and credentials.
func TestConnectivity(ctx context.Context, client *http.Client, p types.Provider, model string) types.ProviderTestResult {
	start := time.Now()
	if client == nil {
		client = &http.Client{Timeout: 20 * time.Second}
	}
	if model == "" {
		if active := p.ActiveModels(); len(active) > 0 {
			model = active[0]
		} else if len(p.Models) > 0 {
			model = p.Models[0]
		} else if len(p.AvailableModels) > 0 {
			model = p.AvailableModels[0]
		} else if preset, ok := FindPreset(p.Preset); ok && len(preset.Models) > 0 {
			model = preset.Models[0]
		}
	}
	res := types.ProviderTestResult{
		Model:    model,
		TestedAt: types.NowRFC3339(),
	}
	if model == "" {
		res.Error = "no model configured for test"
		return res
	}
	base := strings.TrimRight(strings.TrimSpace(p.BaseURL), "/")
	if base == "" {
		if preset, ok := FindPreset(p.Preset); ok {
			base = preset.BaseURL
		}
	}
	if base == "" {
		res.Error = "baseUrl is empty"
		return res
	}

	canon := &translate.CanonicalRequest{
		Model:     model,
		MaxTokens: 16,
		Stream:    false,
		Messages: []translate.Message{{
			Role:  "user",
			Parts: []translate.ContentPart{{Type: "text", Text: "Reply with OK."}},
		}},
	}
	reqBytes, err := translate.EncodeRequest(p.Protocol, canon)
	if err != nil {
		res.Error = err.Error()
		return res
	}

	targetURL := BuildUpstreamURL(base, translate.UpstreamPath(p.Protocol, model, false))
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, targetURL, bytes.NewReader(reqBytes))
	if err != nil {
		res.Error = err.Error()
		return res
	}
	req.Header.Set("Content-Type", "application/json")
	if key, ok := PickKey(p, nil); ok {
		ApplyUpstreamAuth(req, p.Protocol, key.Secret)
	} else if p.Protocol != types.ProtocolOllama {
		res.Error = "no enabled API key configured"
		return res
	}

	resp, err := client.Do(req)
	res.LatencyMs = time.Since(start).Milliseconds()
	if err != nil {
		res.Error = err.Error()
		return res
	}
	defer resp.Body.Close()

	res.StatusCode = resp.StatusCode
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		res.Ok = true
		res.ReplyPreview = translate.ExtractPreviewText(p.Protocol, body)
		if res.ReplyPreview == "" {
			res.ReplyPreview = "OK"
		}
		return res
	}
	errSnippet := strings.TrimSpace(string(body))
	if len(errSnippet) > 300 {
		errSnippet = errSnippet[:300]
	}
	res.Error = fmt.Sprintf("HTTP %d: %s", resp.StatusCode, errSnippet)
	return res
}
