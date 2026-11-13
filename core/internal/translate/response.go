package translate

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/falcon-gateway/falcon/core/internal/types"
)

// DecodeResponse parses a non-streaming JSON response of protocol fromProto into CanonicalResponse.
func DecodeResponse(fromProto types.Protocol, raw []byte) (*CanonicalResponse, error) {
	var body map[string]any
	if err := json.Unmarshal(raw, &body); err != nil {
		return nil, fmt.Errorf("invalid response JSON: %w", err)
	}
	resp := &CanonicalResponse{
		ID:    asString(body["id"]),
		Model: asString(body["model"]),
	}
	if resp.ID == "" {
		resp.ID = fmt.Sprintf("resp_%d", time.Now().UnixNano())
	}

	switch fromProto {
	case types.ProtocolOpenAI:
		if choices, ok := body["choices"].([]any); ok && len(choices) > 0 {
			if c0, ok := choices[0].(map[string]any); ok {
				resp.FinishReason = normalizeFinishReason(asString(c0["finish_reason"]))
				if msg, ok := c0["message"].(map[string]any); ok {
					if rc := asString(msg["reasoning_content"]); rc != "" {
						resp.Parts = append(resp.Parts, ContentPart{Type: "thinking", Text: rc})
					}
					if content := asString(msg["content"]); content != "" {
						resp.Parts = append(resp.Parts, ContentPart{Type: "text", Text: content})
					}
					if tcs, ok := msg["tool_calls"].([]any); ok {
						for _, rtc := range tcs {
							tc, ok := rtc.(map[string]any)
							if !ok {
								continue
							}
							fn, _ := tc["function"].(map[string]any)
							var args any
							_ = json.Unmarshal([]byte(asString(fn["arguments"])), &args)
							if args == nil {
								args = map[string]any{}
							}
							resp.Parts = append(resp.Parts, ContentPart{
								Type:      "tool_use",
								ToolID:    asString(tc["id"]),
								ToolName:  asString(fn["name"]),
								ToolInput: args,
							})
						}
					}
				}
			}
		}
		if u, ok := body["usage"].(map[string]any); ok {
			resp.Usage = Usage{
				InputTokens:  asInt64(u["prompt_tokens"]),
				OutputTokens: asInt64(u["completion_tokens"]),
				TotalTokens:  asInt64(u["total_tokens"]),
			}
		}

	case types.ProtocolResponses:
		resp.FinishReason = "stop"
		if outArr, ok := body["output"].([]any); ok {
			for _, ro := range outArr {
				om, ok := ro.(map[string]any)
				if !ok {
					continue
				}
				switch asString(om["type"]) {
				case "message":
					if contentArr, ok := om["content"].([]any); ok {
						for _, rc := range contentArr {
							cm, ok := rc.(map[string]any)
							if !ok {
								continue
							}
							if txt := asString(cm["text"]); txt != "" {
								resp.Parts = append(resp.Parts, ContentPart{Type: "text", Text: txt})
							}
						}
					}
				case "function_call":
					resp.FinishReason = "tool_calls"
					var args any
					_ = json.Unmarshal([]byte(asString(om["arguments"])), &args)
					if args == nil {
						args = map[string]any{}
					}
					resp.Parts = append(resp.Parts, ContentPart{
						Type:      "tool_use",
						ToolID:    asString(om["call_id"]),
						ToolName:  asString(om["name"]),
						ToolInput: args,
					})
				}
			}
		}
		if u, ok := body["usage"].(map[string]any); ok {
			resp.Usage = Usage{
				InputTokens:  asInt64(u["input_tokens"]),
				OutputTokens: asInt64(u["output_tokens"]),
				TotalTokens:  asInt64(u["total_tokens"]),
			}
		}

	case types.ProtocolAnthropic:
		resp.FinishReason = normalizeFinishReason(asString(body["stop_reason"]))
		if contentArr, ok := body["content"].([]any); ok {
			for _, rc := range contentArr {
				cm, ok := rc.(map[string]any)
				if !ok {
					continue
				}
				switch asString(cm["type"]) {
				case "text":
					resp.Parts = append(resp.Parts, ContentPart{Type: "text", Text: asString(cm["text"])})
				case "thinking":
					resp.Parts = append(resp.Parts, ContentPart{Type: "thinking", Text: asString(cm["thinking"])})
				case "tool_use":
					resp.Parts = append(resp.Parts, ContentPart{
						Type:      "tool_use",
						ToolID:    asString(cm["id"]),
						ToolName:  asString(cm["name"]),
						ToolInput: cm["input"],
					})
				}
			}
		}
		if u, ok := body["usage"].(map[string]any); ok {
			inTok := asInt64(u["input_tokens"])
			outTok := asInt64(u["output_tokens"])
			resp.Usage = Usage{InputTokens: inTok, OutputTokens: outTok, TotalTokens: inTok + outTok}
		}

	case types.ProtocolGemini:
		resp.FinishReason = "stop"
		if cands, ok := body["candidates"].([]any); ok && len(cands) > 0 {
			if c0, ok := cands[0].(map[string]any); ok {
				resp.FinishReason = normalizeFinishReason(asString(c0["finishReason"]))
				if content, ok := c0["content"].(map[string]any); ok {
					if parts, ok := content["parts"].([]any); ok {
						for _, rp := range parts {
							pm, ok := rp.(map[string]any)
							if !ok {
								continue
							}
							if txt := asString(pm["text"]); txt != "" {
								if thought, _ := pm["thought"].(bool); thought {
									resp.Parts = append(resp.Parts, ContentPart{Type: "thinking", Text: txt})
								} else {
									resp.Parts = append(resp.Parts, ContentPart{Type: "text", Text: txt})
								}
							} else if fc, ok := pm["functionCall"].(map[string]any); ok {
								resp.FinishReason = "tool_calls"
								resp.Parts = append(resp.Parts, ContentPart{
									Type:      "tool_use",
									ToolID:    "call_" + asString(fc["name"]),
									ToolName:  asString(fc["name"]),
									ToolInput: fc["args"],
								})
							}
						}
					}
				}
			}
		}
		if um, ok := body["usageMetadata"].(map[string]any); ok {
			inTok := asInt64(um["promptTokenCount"])
			outTok := asInt64(um["candidatesTokenCount"])
			tot := asInt64(um["totalTokenCount"])
			if tot == 0 {
				tot = inTok + outTok
			}
			resp.Usage = Usage{InputTokens: inTok, OutputTokens: outTok, TotalTokens: tot}
		}

	case types.ProtocolOllama:
		resp.FinishReason = "stop"
		if msg, ok := body["message"].(map[string]any); ok {
			if txt := asString(msg["content"]); txt != "" {
				resp.Parts = append(resp.Parts, ContentPart{Type: "text", Text: txt})
			}
		}
		inTok := asInt64(body["prompt_eval_count"])
		outTok := asInt64(body["eval_count"])
		resp.Usage = Usage{InputTokens: inTok, OutputTokens: outTok, TotalTokens: inTok + outTok}
	}

	if resp.Usage.TotalTokens == 0 {
		resp.Usage.TotalTokens = resp.Usage.InputTokens + resp.Usage.OutputTokens
	}
	return resp, nil
}

// EncodeResponse encodes a CanonicalResponse into JSON for protocol toProto.
func EncodeResponse(toProto types.Protocol, resp *CanonicalResponse) ([]byte, error) {
	if resp.ID == "" {
		resp.ID = fmt.Sprintf("resp_%d", time.Now().UnixNano())
	}
	var textBuf, thinkBuf strings.Builder
	var toolUses []ContentPart
	for _, p := range resp.Parts {
		switch p.Type {
		case "text":
			textBuf.WriteString(p.Text)
		case "thinking":
			thinkBuf.WriteString(p.Text)
		case "tool_use":
			toolUses = append(toolUses, p)
		}
	}

	switch toProto {
	case types.ProtocolOpenAI:
		finish := resp.FinishReason
		if finish == "" {
			if len(toolUses) > 0 {
				finish = "tool_calls"
			} else {
				finish = "stop"
			}
		}
		msg := map[string]any{
			"role":    "assistant",
			"content": textBuf.String(),
		}
		if thinkBuf.Len() > 0 {
			msg["reasoning_content"] = thinkBuf.String()
		}
		if len(toolUses) > 0 {
			var tcs []map[string]any
			for idx, tu := range toolUses {
				id := tu.ToolID
				if id == "" {
					id = fmt.Sprintf("call_%d", idx)
				}
				argsBytes, _ := json.Marshal(tu.ToolInput)
				if len(argsBytes) == 0 || string(argsBytes) == "null" {
					argsBytes = []byte("{}")
				}
				tcs = append(tcs, map[string]any{
					"id":   id,
					"type": "function",
					"function": map[string]any{
						"name":      tu.ToolName,
						"arguments": string(argsBytes),
					},
				})
			}
			msg["tool_calls"] = tcs
		}
		return json.Marshal(map[string]any{
			"id":      resp.ID,
			"object":  "chat.completion",
			"created": time.Now().Unix(),
			"model":   resp.Model,
			"choices": []map[string]any{{
				"index":         0,
				"message":       msg,
				"finish_reason": finish,
			}},
			"usage": map[string]any{
				"prompt_tokens":     resp.Usage.InputTokens,
				"completion_tokens": resp.Usage.OutputTokens,
				"total_tokens":      resp.Usage.TotalTokens,
			},
		})

	case types.ProtocolResponses:
		var output []map[string]any
		if textBuf.Len() > 0 || len(toolUses) == 0 {
			output = append(output, map[string]any{
				"id":   "msg_" + resp.ID,
				"type": "message",
				"role": "assistant",
				"content": []map[string]any{{
					"type": "output_text",
					"text": textBuf.String(),
				}},
			})
		}
		for idx, tu := range toolUses {
			id := tu.ToolID
			if id == "" {
				id = fmt.Sprintf("call_%d", idx)
			}
			argsBytes, _ := json.Marshal(tu.ToolInput)
			output = append(output, map[string]any{
				"id":        "fc_" + id,
				"type":      "function_call",
				"call_id":   id,
				"name":      tu.ToolName,
				"arguments": string(argsBytes),
			})
		}
		return json.Marshal(map[string]any{
			"id":          resp.ID,
			"object":      "response",
			"model":       resp.Model,
			"output":      output,
			"output_text": textBuf.String(),
			"status":      "completed",
			"usage": map[string]any{
				"input_tokens":  resp.Usage.InputTokens,
				"output_tokens": resp.Usage.OutputTokens,
				"total_tokens":  resp.Usage.TotalTokens,
			},
		})

	case types.ProtocolAnthropic:
		stopReason := "end_turn"
		if resp.FinishReason == "tool_calls" || len(toolUses) > 0 {
			stopReason = "tool_use"
		} else if resp.FinishReason == "length" {
			stopReason = "max_tokens"
		}
		var content []map[string]any
		if thinkBuf.Len() > 0 {
			content = append(content, map[string]any{"type": "thinking", "thinking": thinkBuf.String()})
		}
		if textBuf.Len() > 0 || len(toolUses) == 0 {
			content = append(content, map[string]any{"type": "text", "text": textBuf.String()})
		}
		for idx, tu := range toolUses {
			id := tu.ToolID
			if id == "" {
				id = fmt.Sprintf("toolu_%d", idx)
			}
			inp := tu.ToolInput
			if inp == nil {
				inp = map[string]any{}
			}
			content = append(content, map[string]any{
				"type":  "tool_use",
				"id":    id,
				"name":  tu.ToolName,
				"input": inp,
			})
		}
		return json.Marshal(map[string]any{
			"id":          resp.ID,
			"type":        "message",
			"role":        "assistant",
			"model":       resp.Model,
			"content":     content,
			"stop_reason": stopReason,
			"usage": map[string]any{
				"input_tokens":  resp.Usage.InputTokens,
				"output_tokens": resp.Usage.OutputTokens,
			},
		})

	case types.ProtocolGemini:
		finish := "STOP"
		if resp.FinishReason == "length" {
			finish = "MAX_TOKENS"
		}
		var parts []map[string]any
		if thinkBuf.Len() > 0 {
			parts = append(parts, map[string]any{"text": thinkBuf.String(), "thought": true})
		}
		if textBuf.Len() > 0 || len(toolUses) == 0 {
			parts = append(parts, map[string]any{"text": textBuf.String()})
		}
		for _, tu := range toolUses {
			args := tu.ToolInput
			if args == nil {
				args = map[string]any{}
			}
			parts = append(parts, map[string]any{
				"functionCall": map[string]any{
					"name": tu.ToolName,
					"args": args,
				},
			})
		}
		return json.Marshal(map[string]any{
			"candidates": []map[string]any{{
				"index":        0,
				"finishReason": finish,
				"content": map[string]any{
					"role":  "model",
					"parts": parts,
				},
			}},
			"usageMetadata": map[string]any{
				"promptTokenCount":     resp.Usage.InputTokens,
				"candidatesTokenCount": resp.Usage.OutputTokens,
				"totalTokenCount":      resp.Usage.TotalTokens,
			},
		})

	case types.ProtocolOllama:
		return json.Marshal(map[string]any{
			"model":             resp.Model,
			"created_at":        time.Now().UTC().Format(time.RFC3339Nano),
			"message":           map[string]any{"role": "assistant", "content": textBuf.String()},
			"done":              true,
			"done_reason":       "stop",
			"prompt_eval_count": resp.Usage.InputTokens,
			"eval_count":        resp.Usage.OutputTokens,
		})
	}
	return nil, fmt.Errorf("unsupported protocol: %s", toProto)
}

// ExtractUsageFromJSON extracts token usage from a raw JSON response in proto format.
func ExtractUsageFromJSON(proto types.Protocol, raw []byte) Usage {
	resp, err := DecodeResponse(proto, raw)
	if err != nil || resp == nil {
		return Usage{}
	}
	return resp.Usage
}

// ExtractPreviewText pulls a short text snippet from a non-streaming response for provider test previews.
func ExtractPreviewText(proto types.Protocol, raw []byte) string {
	resp, err := DecodeResponse(proto, raw)
	if err != nil || resp == nil {
		return ""
	}
	for _, p := range resp.Parts {
		if p.Type == "text" && strings.TrimSpace(p.Text) != "" {
			s := strings.TrimSpace(p.Text)
			if len(s) > 120 {
				return s[:120] + "..."
			}
			return s
		}
	}
	return ""
}
