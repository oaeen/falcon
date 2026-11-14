package translate

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/falcon-gateway/falcon/core/internal/types"
)

func TestCrossProtocolRequestAndResponse(t *testing.T) {
	// Anthropic request -> OpenAI request
	anthReq := []byte(`{
		"model": "claude-sonnet-4",
		"system": "Be concise.",
		"max_tokens": 512,
		"messages": [
			{"role": "user", "content": [{"type": "text", "text": "What is the weather in Tokyo?"}]}
		],
		"tools": [{
			"name": "get_weather",
			"description": "Get weather",
			"input_schema": {"type": "object", "properties": {"city": {"type": "string"}}}
		}],
		"stream": true
	}`)
	canon, err := DecodeRequest(types.ProtocolAnthropic, "", anthReq)
	if err != nil {
		t.Fatalf("DecodeRequest: %v", err)
	}
	if canon.System != "Be concise." || !canon.Stream || len(canon.Tools) != 1 {
		t.Fatalf("unexpected canonical request: %+v", canon)
	}

	openAIBody, err := EncodeRequest(types.ProtocolOpenAI, canon)
	if err != nil {
		t.Fatalf("EncodeRequest OpenAI: %v", err)
	}
	var oaiMap map[string]any
	if err := json.Unmarshal(openAIBody, &oaiMap); err != nil {
		t.Fatal(err)
	}
	msgs := oaiMap["messages"].([]any)
	if len(msgs) != 2 || msgs[0].(map[string]any)["role"] != "system" {
		t.Fatalf("expected system + user messages, got %+v", msgs)
	}

	// OpenAI response -> Gemini response
	oaiResp := []byte(`{
		"id": "chatcmpl-1",
		"model": "gpt-4o",
		"choices": [{
			"index": 0,
			"finish_reason": "tool_calls",
			"message": {
				"role": "assistant",
				"content": "Checking weather.",
				"tool_calls": [{
					"id": "call_1",
					"type": "function",
					"function": {"name": "get_weather", "arguments": "{\"city\":\"Tokyo\"}"}
				}]
			}
		}],
		"usage": {"prompt_tokens": 20, "completion_tokens": 12, "total_tokens": 32}
	}`)
	cResp, err := DecodeResponse(types.ProtocolOpenAI, oaiResp)
	if err != nil {
		t.Fatal(err)
	}
	gemResp, err := EncodeResponse(types.ProtocolGemini, cResp)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(gemResp), `"functionCall"`) || !strings.Contains(string(gemResp), `"promptTokenCount":20`) {
		t.Fatalf("unexpected gemini response: %s", string(gemResp))
	}
}

func TestStreamTranslationOpenAIToAnthropicAndResponses(t *testing.T) {
	st := NewStreamTranslator(types.ProtocolOpenAI, types.ProtocolAnthropic, "claude-sonnet-4")
	chunks := []string{
		`data: {"id":"1","model":"gpt-4o","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}` + "\n\n",
		`data: {"id":"1","model":"gpt-4o","choices":[{"index":0,"delta":{"content":"Hello "},"finish_reason":null}]}` + "\n\n",
		`data: {"id":"1","model":"gpt-4o","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_9","type":"function","function":{"name":"ping","arguments":""}}]},"finish_reason":null}]}` + "\n\n",
		`data: {"id":"1","model":"gpt-4o","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"x\":1}"}}]},"finish_reason":null}]}` + "\n\n",
		`data: {"id":"1","model":"gpt-4o","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}` + "\n\n",
		"data: [DONE]\n\n",
	}
	var out strings.Builder
	for _, c := range chunks {
		out.Write(st.ProcessChunk([]byte(c)))
	}
	out.Write(st.Flush())

	res := out.String()
	for _, want := range []string{"event: message_start", "text_delta", "tool_use", "input_json_delta", "message_delta", `"output_tokens":5`} {
		if !strings.Contains(res, want) {
			t.Fatalf("expected %q in anthropic stream, got:\n%s", want, res)
		}
	}
	if st.Usage.InputTokens != 10 || st.Usage.OutputTokens != 5 {
		t.Fatalf("expected usage 10/5, got %+v", st.Usage)
	}
}

func TestCollectStreamToCanonical(t *testing.T) {
	sse := strings.Join([]string{
		`data: {"id":"cmpl-wb","model":"glm-5.3","choices":[{"index":0,"delta":{"role":"assistant","reasoning_content":"Think..."}}]}`,
		`data: {"id":"cmpl-wb","model":"glm-5.3","choices":[{"index":0,"delta":{"content":"Answer "}}]}`,
		`data: {"id":"cmpl-wb","model":"glm-5.3","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"lookup","arguments":""}}]}}]}`,
		`data: {"id":"cmpl-wb","model":"glm-5.3","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"q\":\"go\"}"}}]}}]}`,
		`data: {"id":"cmpl-wb","model":"glm-5.3","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":12,"completion_tokens":8,"total_tokens":20}}`,
		`data: [DONE]`,
	}, "\n\n") + "\n\n"

	canon, err := CollectStreamToCanonical(types.ProtocolOpenAI, []byte(sse), "fallback")
	if err != nil {
		t.Fatalf("CollectStreamToCanonical failed: %v", err)
	}
	if canon.ID != "cmpl-wb" || canon.Model != "glm-5.3" || canon.FinishReason != "tool_calls" {
		t.Fatalf("unexpected metadata: %+v", canon)
	}
	if canon.Usage.InputTokens != 12 || canon.Usage.OutputTokens != 8 || canon.Usage.TotalTokens != 20 {
		t.Fatalf("unexpected usage: %+v", canon.Usage)
	}
	if len(canon.Parts) != 3 {
		t.Fatalf("expected thinking + text + tool_use parts, got %+v", canon.Parts)
	}
	if canon.Parts[0].Type != "thinking" || canon.Parts[0].Text != "Think..." {
		t.Fatalf("unexpected thinking part: %+v", canon.Parts[0])
	}
	if canon.Parts[1].Type != "text" || canon.Parts[1].Text != "Answer " {
		t.Fatalf("unexpected text part: %+v", canon.Parts[1])
	}
	if canon.Parts[2].Type != "tool_use" || canon.Parts[2].ToolName != "lookup" {
		t.Fatalf("unexpected tool part: %+v", canon.Parts[2])
	}

	oaiJSON, err := EncodeResponse(types.ProtocolOpenAI, canon)
	if err != nil {
		t.Fatalf("EncodeResponse openai: %v", err)
	}
	if !strings.Contains(string(oaiJSON), `"Answer "`) || !strings.Contains(string(oaiJSON), `"lookup"`) {
		t.Fatalf("unexpected openai encoded response: %s", string(oaiJSON))
	}
}
