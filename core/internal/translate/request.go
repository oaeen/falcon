package translate

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/falcon-gateway/falcon/core/internal/types"
)

// DecodeRequest parses a raw JSON request body of protocol fromProto into CanonicalRequest.
func DecodeRequest(fromProto types.Protocol, modelHint string, raw []byte) (*CanonicalRequest, error) {
	var body map[string]any
	if err := json.Unmarshal(raw, &body); err != nil {
		return nil, fmt.Errorf("invalid request JSON: %w", err)
	}
	req := &CanonicalRequest{
		Model: modelHint,
	}
	if m := asString(body["model"]); m != "" {
		req.Model = m
	}
	if b, ok := body["stream"].(bool); ok {
		req.Stream = b
	}

	switch fromProto {
	case types.ProtocolOpenAI, types.ProtocolOllama:
		return decodeOpenAIOrOllamaReq(req, body)
	case types.ProtocolResponses:
		return decodeResponsesReq(req, body)
	case types.ProtocolAnthropic:
		return decodeAnthropicReq(req, body)
	case types.ProtocolGemini:
		return decodeGeminiReq(req, body)
	default:
		return decodeOpenAIOrOllamaReq(req, body)
	}
}

func decodeOpenAIOrOllamaReq(req *CanonicalRequest, body map[string]any) (*CanonicalRequest, error) {
	req.Temperature = asFloatPtr(body["temperature"])
	req.TopP = asFloatPtr(body["top_p"])
	if mt := asInt(body["max_completion_tokens"]); mt > 0 {
		req.MaxTokens = mt
	} else if mt := asInt(body["max_tokens"]); mt > 0 {
		req.MaxTokens = mt
	}
	if opts, ok := body["options"].(map[string]any); ok {
		if req.Temperature == nil {
			req.Temperature = asFloatPtr(opts["temperature"])
		}
		if req.MaxTokens == 0 {
			req.MaxTokens = asInt(opts["num_predict"])
		}
	}
	switch st := body["stop"].(type) {
	case string:
		if st != "" {
			req.Stop = []string{st}
		}
	case []any:
		for _, item := range st {
			if s := asString(item); s != "" {
				req.Stop = append(req.Stop, s)
			}
		}
	}

	if msgs, ok := body["messages"].([]any); ok {
		var sysParts []string
		for _, rawMsg := range msgs {
			mm, ok := rawMsg.(map[string]any)
			if !ok {
				continue
			}
			role := asString(mm["role"])
			if role == "system" || role == "developer" {
				if txt := extractTextFromAny(mm["content"]); txt != "" {
					sysParts = append(sysParts, txt)
				}
				continue
			}
			msg := Message{
				Role:       role,
				ToolCallID: asString(mm["tool_call_id"]),
				Name:       asString(mm["name"]),
			}
			if role == "tool" {
				msg.Parts = append(msg.Parts, ContentPart{
					Type:       "tool_result",
					ToolID:     msg.ToolCallID,
					ToolName:   msg.Name,
					ToolOutput: extractTextFromAny(mm["content"]),
				})
				req.Messages = append(req.Messages, msg)
				continue
			}
			msg.Parts = append(msg.Parts, parseOpenAIContentParts(mm["content"])...)
			if tcs, ok := mm["tool_calls"].([]any); ok {
				for _, rtc := range tcs {
					tc, ok := rtc.(map[string]any)
					if !ok {
						continue
					}
					fn, _ := tc["function"].(map[string]any)
					var args any
					if rawArgs := asString(fn["arguments"]); rawArgs != "" {
						_ = json.Unmarshal([]byte(rawArgs), &args)
					}
					if args == nil {
						args = map[string]any{}
					}
					msg.Parts = append(msg.Parts, ContentPart{
						Type:      "tool_use",
						ToolID:    asString(tc["id"]),
						ToolName:  asString(fn["name"]),
						ToolInput: args,
					})
				}
			}
			req.Messages = append(req.Messages, msg)
		}
		if len(sysParts) > 0 {
			req.System = strings.Join(sysParts, "\n")
		}
	}

	if tools, ok := body["tools"].([]any); ok {
		for _, rt := range tools {
			tm, ok := rt.(map[string]any)
			if !ok {
				continue
			}
			fn, _ := tm["function"].(map[string]any)
			if fn == nil {
				fn = tm
			}
			params, _ := fn["parameters"].(map[string]any)
			req.Tools = append(req.Tools, ToolDef{
				Name:        asString(fn["name"]),
				Description: asString(fn["description"]),
				Parameters:  params,
			})
		}
	}
	req.ToolChoice = body["tool_choice"]
	return req, nil
}

func decodeResponsesReq(req *CanonicalRequest, body map[string]any) (*CanonicalRequest, error) {
	req.System = asString(body["instructions"])
	req.Temperature = asFloatPtr(body["temperature"])
	req.TopP = asFloatPtr(body["top_p"])
	req.MaxTokens = asInt(body["max_output_tokens"])

	switch inp := body["input"].(type) {
	case string:
		req.Messages = append(req.Messages, Message{
			Role:  "user",
			Parts: []ContentPart{{Type: "text", Text: inp}},
		})
	case []any:
		for _, item := range inp {
			im, ok := item.(map[string]any)
			if !ok {
				continue
			}
			itemType := asString(im["type"])
			switch itemType {
			case "function_call":
				var args any
				_ = json.Unmarshal([]byte(asString(im["arguments"])), &args)
				if args == nil {
					args = map[string]any{}
				}
				req.Messages = append(req.Messages, Message{
					Role: "assistant",
					Parts: []ContentPart{{
						Type:      "tool_use",
						ToolID:    asString(im["call_id"]),
						ToolName:  asString(im["name"]),
						ToolInput: args,
					}},
				})
			case "function_call_output":
				req.Messages = append(req.Messages, Message{
					Role:       "tool",
					ToolCallID: asString(im["call_id"]),
					Parts: []ContentPart{{
						Type:       "tool_result",
						ToolID:     asString(im["call_id"]),
						ToolOutput: asString(im["output"]),
					}},
				})
			default:
				role := asString(im["role"])
				if role == "" {
					role = "user"
				}
				if role == "system" || role == "developer" {
					txt := extractTextFromAny(im["content"])
					if txt != "" {
						if req.System != "" {
							req.System += "\n"
						}
						req.System += txt
					}
					continue
				}
				req.Messages = append(req.Messages, Message{
					Role:  role,
					Parts: parseOpenAIContentParts(im["content"]),
				})
			}
		}
	}

	if tools, ok := body["tools"].([]any); ok {
		for _, rt := range tools {
			tm, ok := rt.(map[string]any)
			if !ok {
				continue
			}
			params, _ := tm["parameters"].(map[string]any)
			if fn, ok := tm["function"].(map[string]any); ok {
				req.Tools = append(req.Tools, ToolDef{
					Name:        asString(fn["name"]),
					Description: asString(fn["description"]),
					Parameters:  mapFromAny(fn["parameters"]),
				})
			} else {
				req.Tools = append(req.Tools, ToolDef{
					Name:        asString(tm["name"]),
					Description: asString(tm["description"]),
					Parameters:  params,
				})
			}
		}
	}
	return req, nil
}

func decodeAnthropicReq(req *CanonicalRequest, body map[string]any) (*CanonicalRequest, error) {
	req.Temperature = asFloatPtr(body["temperature"])
	req.TopP = asFloatPtr(body["top_p"])
	req.MaxTokens = asInt(body["max_tokens"])
	switch sys := body["system"].(type) {
	case string:
		req.System = sys
	case []any:
		var sb []string
		for _, s := range sys {
			if sm, ok := s.(map[string]any); ok {
				if t := asString(sm["text"]); t != "" {
					sb = append(sb, t)
				}
			}
		}
		req.System = strings.Join(sb, "\n")
	}
	if ss, ok := body["stop_sequences"].([]any); ok {
		for _, item := range ss {
			if s := asString(item); s != "" {
				req.Stop = append(req.Stop, s)
			}
		}
	}
	if msgs, ok := body["messages"].([]any); ok {
		for _, rawMsg := range msgs {
			mm, ok := rawMsg.(map[string]any)
			if !ok {
				continue
			}
			role := asString(mm["role"])
			var parts []ContentPart
			switch c := mm["content"].(type) {
			case string:
				if c != "" {
					parts = append(parts, ContentPart{Type: "text", Text: c})
				}
			case []any:
				for _, blk := range c {
					bm, ok := blk.(map[string]any)
					if !ok {
						continue
					}
					switch asString(bm["type"]) {
					case "text":
						parts = append(parts, ContentPart{Type: "text", Text: asString(bm["text"])})
					case "thinking":
						parts = append(parts, ContentPart{Type: "thinking", Text: asString(bm["thinking"])})
					case "image":
						if src, ok := bm["source"].(map[string]any); ok {
							if asString(src["type"]) == "base64" {
								parts = append(parts, ContentPart{
									Type:      "image",
									MediaType: asString(src["media_type"]),
									ImageData: asString(src["data"]),
								})
							} else if u := asString(src["url"]); u != "" {
								parts = append(parts, ContentPart{Type: "image", ImageURL: u})
							}
						}
					case "tool_use":
						parts = append(parts, ContentPart{
							Type:      "tool_use",
							ToolID:    asString(bm["id"]),
							ToolName:  asString(bm["name"]),
							ToolInput: bm["input"],
						})
					case "tool_result":
						isErr, _ := bm["is_error"].(bool)
						parts = append(parts, ContentPart{
							Type:       "tool_result",
							ToolID:     asString(bm["tool_use_id"]),
							ToolOutput: extractTextFromAny(bm["content"]),
							IsError:    isErr,
						})
					}
				}
			}
			req.Messages = append(req.Messages, Message{Role: role, Parts: parts})
		}
	}
	if tools, ok := body["tools"].([]any); ok {
		for _, rt := range tools {
			tm, ok := rt.(map[string]any)
			if !ok {
				continue
			}
			req.Tools = append(req.Tools, ToolDef{
				Name:        asString(tm["name"]),
				Description: asString(tm["description"]),
				Parameters:  mapFromAny(tm["input_schema"]),
			})
		}
	}
	return req, nil
}

func decodeGeminiReq(req *CanonicalRequest, body map[string]any) (*CanonicalRequest, error) {
	if si, ok := body["systemInstruction"].(map[string]any); ok {
		if parts, ok := si["parts"].([]any); ok {
			var sb []string
			for _, p := range parts {
				if pm, ok := p.(map[string]any); ok {
					if t := asString(pm["text"]); t != "" {
						sb = append(sb, t)
					}
				}
			}
			req.System = strings.Join(sb, "\n")
		}
	}
	if gc, ok := body["generationConfig"].(map[string]any); ok {
		req.Temperature = asFloatPtr(gc["temperature"])
		req.TopP = asFloatPtr(gc["topP"])
		req.MaxTokens = asInt(gc["maxOutputTokens"])
		if ss, ok := gc["stopSequences"].([]any); ok {
			for _, item := range ss {
				if s := asString(item); s != "" {
					req.Stop = append(req.Stop, s)
				}
			}
		}
	}
	if contents, ok := body["contents"].([]any); ok {
		for _, rc := range contents {
			cm, ok := rc.(map[string]any)
			if !ok {
				continue
			}
			role := asString(cm["role"])
			if role == "model" {
				role = "assistant"
			} else if role == "" {
				role = "user"
			}
			var parts []ContentPart
			if rparts, ok := cm["parts"].([]any); ok {
				for _, rp := range rparts {
					pm, ok := rp.(map[string]any)
					if !ok {
						continue
					}
					if t := asString(pm["text"]); t != "" {
						if thought, _ := pm["thought"].(bool); thought {
							parts = append(parts, ContentPart{Type: "thinking", Text: t})
						} else {
							parts = append(parts, ContentPart{Type: "text", Text: t})
						}
					} else if fc, ok := pm["functionCall"].(map[string]any); ok {
						parts = append(parts, ContentPart{
							Type:      "tool_use",
							ToolID:    asString(fc["name"]),
							ToolName:  asString(fc["name"]),
							ToolInput: fc["args"],
						})
					} else if fr, ok := pm["functionResponse"].(map[string]any); ok {
						b, _ := json.Marshal(fr["response"])
						parts = append(parts, ContentPart{
							Type:       "tool_result",
							ToolID:     asString(fr["name"]),
							ToolName:   asString(fr["name"]),
							ToolOutput: string(b),
						})
					} else if idata, ok := pm["inlineData"].(map[string]any); ok {
						parts = append(parts, ContentPart{
							Type:      "image",
							MediaType: asString(idata["mimeType"]),
							ImageData: asString(idata["data"]),
						})
					}
				}
			}
			req.Messages = append(req.Messages, Message{Role: role, Parts: parts})
		}
	}
	if tools, ok := body["tools"].([]any); ok {
		for _, rt := range tools {
			tm, ok := rt.(map[string]any)
			if !ok {
				continue
			}
			if fds, ok := tm["functionDeclarations"].([]any); ok {
				for _, rfd := range fds {
					fd, ok := rfd.(map[string]any)
					if !ok {
						continue
					}
					req.Tools = append(req.Tools, ToolDef{
						Name:        asString(fd["name"]),
						Description: asString(fd["description"]),
						Parameters:  mapFromAny(fd["parameters"]),
					})
				}
			}
		}
	}
	return req, nil
}

// EncodeRequest encodes CanonicalRequest into JSON for target protocol toProto.
func EncodeRequest(toProto types.Protocol, req *CanonicalRequest) ([]byte, error) {
	switch toProto {
	case types.ProtocolOpenAI:
		return encodeOpenAIReq(req)
	case types.ProtocolResponses:
		return encodeResponsesReq(req)
	case types.ProtocolAnthropic:
		return encodeAnthropicReq(req)
	case types.ProtocolGemini:
		return encodeGeminiReq(req)
	case types.ProtocolOllama:
		return encodeOllamaReq(req)
	default:
		return encodeOpenAIReq(req)
	}
}

func encodeOpenAIReq(req *CanonicalRequest) ([]byte, error) {
	var msgs []map[string]any
	if req.System != "" {
		msgs = append(msgs, map[string]any{"role": "system", "content": req.System})
	}
	for _, m := range req.Messages {
		if m.Role == "tool" || (len(m.Parts) > 0 && m.Parts[0].Type == "tool_result") {
			for _, p := range m.Parts {
				if p.Type == "tool_result" {
					callID := p.ToolID
					if callID == "" {
						callID = m.ToolCallID
					}
					msgs = append(msgs, map[string]any{
						"role":         "tool",
						"tool_call_id": callID,
						"content":      p.ToolOutput,
					})
				} else if p.Type == "text" && p.Text != "" {
					msgs = append(msgs, map[string]any{
						"role":    "user",
						"content": p.Text,
					})
				}
			}
			continue
		}
		var textBuf strings.Builder
		var contentArr []map[string]any
		var toolCalls []map[string]any
		hasImage := false
		for _, p := range m.Parts {
			switch p.Type {
			case "text":
				textBuf.WriteString(p.Text)
				contentArr = append(contentArr, map[string]any{"type": "text", "text": p.Text})
			case "image":
				hasImage = true
				u := p.ImageURL
				if u == "" && p.ImageData != "" {
					mt := p.MediaType
					if mt == "" {
						mt = "image/png"
					}
					u = "data:" + mt + ";base64," + p.ImageData
				}
				contentArr = append(contentArr, map[string]any{
					"type":      "image_url",
					"image_url": map[string]any{"url": u},
				})
			case "tool_use":
				b, _ := json.Marshal(p.ToolInput)
				if len(b) == 0 || string(b) == "null" {
					b = []byte("{}")
				}
				id := p.ToolID
				if id == "" {
					id = "call_" + p.ToolName
				}
				toolCalls = append(toolCalls, map[string]any{
					"id":   id,
					"type": "function",
					"function": map[string]any{
						"name":      p.ToolName,
						"arguments": string(b),
					},
				})
			}
		}
		msgMap := map[string]any{"role": m.Role}
		if hasImage {
			msgMap["content"] = contentArr
		} else if textBuf.Len() > 0 || len(toolCalls) == 0 {
			msgMap["content"] = textBuf.String()
		} else {
			msgMap["content"] = nil
		}
		if len(toolCalls) > 0 {
			msgMap["tool_calls"] = toolCalls
		}
		msgs = append(msgs, msgMap)
	}

	out := map[string]any{
		"model":    req.Model,
		"messages": msgs,
		"stream":   req.Stream,
	}
	if req.Stream {
		out["stream_options"] = map[string]any{"include_usage": true}
	}
	if req.MaxTokens > 0 {
		out["max_tokens"] = req.MaxTokens
	}
	if req.Temperature != nil {
		out["temperature"] = *req.Temperature
	}
	if req.TopP != nil {
		out["top_p"] = *req.TopP
	}
	if len(req.Stop) > 0 {
		out["stop"] = req.Stop
	}
	if len(req.Tools) > 0 {
		var tools []map[string]any
		for _, t := range req.Tools {
			tools = append(tools, map[string]any{
				"type": "function",
				"function": map[string]any{
					"name":        t.Name,
					"description": t.Description,
					"parameters":  t.Parameters,
				},
			})
		}
		out["tools"] = tools
	}
	return json.Marshal(out)
}

func encodeResponsesReq(req *CanonicalRequest) ([]byte, error) {
	var input []any
	for _, m := range req.Messages {
		for _, p := range m.Parts {
			switch p.Type {
			case "tool_use":
				b, _ := json.Marshal(p.ToolInput)
				input = append(input, map[string]any{
					"type":      "function_call",
					"call_id":   p.ToolID,
					"name":      p.ToolName,
					"arguments": string(b),
				})
			case "tool_result":
				input = append(input, map[string]any{
					"type":    "function_call_output",
					"call_id": p.ToolID,
					"output":  p.ToolOutput,
				})
			case "text":
				contentType := "input_text"
				if m.Role == "assistant" {
					contentType = "output_text"
				}
				input = append(input, map[string]any{
					"role": m.Role,
					"content": []map[string]any{{
						"type": contentType,
						"text": p.Text,
					}},
				})
			}
		}
	}
	out := map[string]any{
		"model":  req.Model,
		"input":  input,
		"stream": req.Stream,
	}
	if req.System != "" {
		out["instructions"] = req.System
	}
	if req.MaxTokens > 0 {
		out["max_output_tokens"] = req.MaxTokens
	}
	if req.Temperature != nil {
		out["temperature"] = *req.Temperature
	}
	if len(req.Tools) > 0 {
		var tools []map[string]any
		for _, t := range req.Tools {
			tools = append(tools, map[string]any{
				"type":        "function",
				"name":        t.Name,
				"description": t.Description,
				"parameters":  t.Parameters,
			})
		}
		out["tools"] = tools
	}
	return json.Marshal(out)
}

func encodeAnthropicReq(req *CanonicalRequest) ([]byte, error) {
	maxTokens := req.MaxTokens
	if maxTokens <= 0 {
		maxTokens = 4096
	}
	var msgs []map[string]any
	for _, m := range req.Messages {
		role := m.Role
		if role == "tool" {
			role = "user"
		}
		var blocks []map[string]any
		for _, p := range m.Parts {
			switch p.Type {
			case "text":
				blocks = append(blocks, map[string]any{"type": "text", "text": p.Text})
			case "image":
				if p.ImageData != "" {
					mt := p.MediaType
					if mt == "" {
						mt = "image/png"
					}
					blocks = append(blocks, map[string]any{
						"type": "image",
						"source": map[string]any{
							"type":       "base64",
							"media_type": mt,
							"data":       p.ImageData,
						},
					})
				} else if p.ImageURL != "" {
					blocks = append(blocks, map[string]any{
						"type": "image",
						"source": map[string]any{
							"type": "url",
							"url":  p.ImageURL,
						},
					})
				}
			case "tool_use":
				inp := p.ToolInput
				if inp == nil {
					inp = map[string]any{}
				}
				id := p.ToolID
				if id == "" {
					id = "toolu_" + p.ToolName
				}
				blocks = append(blocks, map[string]any{
					"type":  "tool_use",
					"id":    id,
					"name":  p.ToolName,
					"input": inp,
				})
			case "tool_result":
				blocks = append(blocks, map[string]any{
					"type":        "tool_result",
					"tool_use_id": p.ToolID,
					"content":     p.ToolOutput,
					"is_error":    p.IsError,
				})
			}
		}
		if len(blocks) == 0 {
			blocks = append(blocks, map[string]any{"type": "text", "text": ""})
		}
		// Anthropic merges consecutive messages with the same role
		if len(msgs) > 0 && msgs[len(msgs)-1]["role"] == role {
			prevBlocks := msgs[len(msgs)-1]["content"].([]map[string]any)
			msgs[len(msgs)-1]["content"] = append(prevBlocks, blocks...)
		} else {
			msgs = append(msgs, map[string]any{"role": role, "content": blocks})
		}
	}

	out := map[string]any{
		"model":      req.Model,
		"max_tokens": maxTokens,
		"messages":   msgs,
		"stream":     req.Stream,
	}
	if req.System != "" {
		out["system"] = req.System
	}
	if req.Temperature != nil {
		out["temperature"] = *req.Temperature
	}
	if req.TopP != nil {
		out["top_p"] = *req.TopP
	}
	if len(req.Stop) > 0 {
		out["stop_sequences"] = req.Stop
	}
	if len(req.Tools) > 0 {
		var tools []map[string]any
		for _, t := range req.Tools {
			schema := t.Parameters
			if schema == nil {
				schema = map[string]any{"type": "object", "properties": map[string]any{}}
			}
			tools = append(tools, map[string]any{
				"name":         t.Name,
				"description":  t.Description,
				"input_schema": schema,
			})
		}
		out["tools"] = tools
	}
	return json.Marshal(out)
}

func encodeGeminiReq(req *CanonicalRequest) ([]byte, error) {
	var contents []map[string]any
	for _, m := range req.Messages {
		role := "user"
		if m.Role == "assistant" {
			role = "model"
		}
		var parts []map[string]any
		for _, p := range m.Parts {
			switch p.Type {
			case "text":
				parts = append(parts, map[string]any{"text": p.Text})
			case "image":
				if p.ImageData != "" {
					mt := p.MediaType
					if mt == "" {
						mt = "image/png"
					}
					parts = append(parts, map[string]any{
						"inlineData": map[string]any{"mimeType": mt, "data": p.ImageData},
					})
				}
			case "tool_use":
				args := p.ToolInput
				if args == nil {
					args = map[string]any{}
				}
				parts = append(parts, map[string]any{
					"functionCall": map[string]any{
						"name": p.ToolName,
						"args": args,
					},
				})
			case "tool_result":
				name := p.ToolName
				if name == "" {
					name = p.ToolID
				}
				var respObj any
				if err := json.Unmarshal([]byte(p.ToolOutput), &respObj); err != nil {
					respObj = map[string]any{"result": p.ToolOutput}
				}
				parts = append(parts, map[string]any{
					"functionResponse": map[string]any{
						"name":     name,
						"response": respObj,
					},
				})
			}
		}
		if len(parts) > 0 {
			contents = append(contents, map[string]any{"role": role, "parts": parts})
		}
	}
	out := map[string]any{
		"contents": contents,
	}
	if req.System != "" {
		out["systemInstruction"] = map[string]any{
			"parts": []map[string]any{{"text": req.System}},
		}
	}
	gc := map[string]any{}
	if req.Temperature != nil {
		gc["temperature"] = *req.Temperature
	}
	if req.TopP != nil {
		gc["topP"] = *req.TopP
	}
	if req.MaxTokens > 0 {
		gc["maxOutputTokens"] = req.MaxTokens
	}
	if len(req.Stop) > 0 {
		gc["stopSequences"] = req.Stop
	}
	if len(gc) > 0 {
		out["generationConfig"] = gc
	}
	if len(req.Tools) > 0 {
		var fds []map[string]any
		for _, t := range req.Tools {
			fds = append(fds, map[string]any{
				"name":        t.Name,
				"description": t.Description,
				"parameters":  t.Parameters,
			})
		}
		out["tools"] = []map[string]any{{"functionDeclarations": fds}}
	}
	return json.Marshal(out)
}

func encodeOllamaReq(req *CanonicalRequest) ([]byte, error) {
	var msgs []map[string]any
	if req.System != "" {
		msgs = append(msgs, map[string]any{"role": "system", "content": req.System})
	}
	for _, m := range req.Messages {
		var text strings.Builder
		for _, p := range m.Parts {
			if p.Type == "text" {
				text.WriteString(p.Text)
			} else if p.Type == "tool_result" {
				text.WriteString(p.ToolOutput)
			}
		}
		msgs = append(msgs, map[string]any{
			"role":    m.Role,
			"content": text.String(),
		})
	}
	out := map[string]any{
		"model":    req.Model,
		"messages": msgs,
		"stream":   req.Stream,
	}
	return json.Marshal(out)
}

func parseOpenAIContentParts(v any) []ContentPart {
	switch c := v.(type) {
	case string:
		if c == "" {
			return nil
		}
		return []ContentPart{{Type: "text", Text: c}}
	case []any:
		var parts []ContentPart
		for _, item := range c {
			pm, ok := item.(map[string]any)
			if !ok {
				continue
			}
			typ := asString(pm["type"])
			switch typ {
			case "text", "input_text", "output_text":
				parts = append(parts, ContentPart{Type: "text", Text: asString(pm["text"])})
			case "image_url", "input_image":
				if iu, ok := pm["image_url"].(map[string]any); ok {
					parts = append(parts, ContentPart{Type: "image", ImageURL: asString(iu["url"])})
				} else if u := asString(pm["image_url"]); u != "" {
					parts = append(parts, ContentPart{Type: "image", ImageURL: u})
				}
			}
		}
		return parts
	}
	return nil
}

func extractTextFromAny(v any) string {
	switch c := v.(type) {
	case string:
		return c
	case []any:
		var sb []string
		for _, item := range c {
			if m, ok := item.(map[string]any); ok {
				if t := asString(m["text"]); t != "" {
					sb = append(sb, t)
				}
			} else if s, ok := item.(string); ok {
				sb = append(sb, s)
			}
		}
		return strings.Join(sb, "\n")
	default:
		if v == nil {
			return ""
		}
		b, _ := json.Marshal(v)
		return string(b)
	}
}

func mapFromAny(v any) map[string]any {
	if m, ok := v.(map[string]any); ok {
		return m
	}
	return nil
}
