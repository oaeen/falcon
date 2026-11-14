package translate

import (
	"bytes"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/falcon-gateway/falcon/core/internal/types"
)

// StreamTranslator converts streaming chunks between any two supported protocols,
// and tracks cumulative token usage.
type StreamTranslator struct {
	FromProto types.Protocol
	ToProto   types.Protocol
	Model     string

	buf           bytes.Buffer
	Usage         Usage
	started       bool
	textBlockOpen bool
	nextBlockIdx  int
	toolBlocks    map[int]int // toolIndex -> anthropic content block index
	anthropicIdx  map[int]string
	msgID         string
}

// NewStreamTranslator creates a stream translator from fromProto to toProto.
func NewStreamTranslator(fromProto, toProto types.Protocol, model string) *StreamTranslator {
	return &StreamTranslator{
		FromProto:    fromProto,
		ToProto:      toProto,
		Model:        model,
		toolBlocks:   make(map[int]int),
		anthropicIdx: make(map[int]string),
		msgID:        fmt.Sprintf("msg_%d", time.Now().UnixNano()),
	}
}

// ProcessChunk ingests raw upstream stream bytes and returns translated downstream bytes.
func (st *StreamTranslator) ProcessChunk(chunk []byte) []byte {
	st.buf.Write(chunk)
	data := st.buf.Bytes()
	var out bytes.Buffer

	for {
		idx := bytes.IndexByte(data, '\n')
		if idx < 0 {
			break
		}
		line := strings.TrimRight(string(data[:idx+1]), "\r\n")
		data = data[idx+1:]
		events := st.parseLine(line)
		for _, ev := range events {
			if ev.Usage != nil {
				if ev.Usage.InputTokens > 0 {
					st.Usage.InputTokens = ev.Usage.InputTokens
				}
				if ev.Usage.OutputTokens > 0 {
					st.Usage.OutputTokens = ev.Usage.OutputTokens
				}
				if ev.Usage.TotalTokens > 0 {
					st.Usage.TotalTokens = ev.Usage.TotalTokens
				} else {
					st.Usage.TotalTokens = st.Usage.InputTokens + st.Usage.OutputTokens
				}
			}
			out.Write(st.encodeEvent(ev))
		}
	}
	st.buf.Reset()
	st.buf.Write(data)
	return out.Bytes()
}

// Flush flushes any remaining buffered stream data and emits terminal SSE markers if needed.
func (st *StreamTranslator) Flush() []byte {
	var out bytes.Buffer
	if st.buf.Len() > 0 {
		line := strings.TrimRight(st.buf.String(), "\r\n")
		st.buf.Reset()
		for _, ev := range st.parseLine(line) {
			out.Write(st.encodeEvent(ev))
		}
	}
	return out.Bytes()
}

func (st *StreamTranslator) parseLine(line string) []StreamEvent {
	trimmed := strings.TrimSpace(line)
	if trimmed == "" || strings.HasPrefix(trimmed, "event:") || strings.HasPrefix(trimmed, ":") {
		return nil
	}
	if st.FromProto == types.ProtocolOllama {
		return st.parseOllamaLine(trimmed)
	}
	if !strings.HasPrefix(trimmed, "data:") {
		return nil
	}
	payload := strings.TrimSpace(strings.TrimPrefix(trimmed, "data:"))
	if payload == "" {
		return nil
	}
	if payload == "[DONE]" {
		if !st.started {
			return nil
		}
		return []StreamEvent{{Kind: EventFinish, FinishReason: "stop", Usage: &st.Usage}}
	}
	var obj map[string]any
	if err := json.Unmarshal([]byte(payload), &obj); err != nil {
		return nil
	}
	switch st.FromProto {
	case types.ProtocolOpenAI:
		return st.parseOpenAIEvent(obj)
	case types.ProtocolAnthropic:
		return st.parseAnthropicEvent(obj)
	case types.ProtocolResponses:
		return st.parseResponsesEvent(obj)
	case types.ProtocolGemini:
		return st.parseGeminiEvent(obj)
	default:
		return st.parseOpenAIEvent(obj)
	}
}

func (st *StreamTranslator) parseOpenAIEvent(obj map[string]any) []StreamEvent {
	var events []StreamEvent
	if !st.started {
		st.started = true
		events = append(events, StreamEvent{Kind: EventStart, ID: asString(obj["id"]), Model: asString(obj["model"])})
	}
	if u, ok := obj["usage"].(map[string]any); ok {
		usage := &Usage{
			InputTokens:  asInt64(u["prompt_tokens"]),
			OutputTokens: asInt64(u["completion_tokens"]),
			TotalTokens:  asInt64(u["total_tokens"]),
		}
		events = append(events, StreamEvent{Kind: EventFinish, Usage: usage})
	}
	choices, _ := obj["choices"].([]any)
	for _, rc := range choices {
		cm, ok := rc.(map[string]any)
		if !ok {
			continue
		}
		if delta, ok := cm["delta"].(map[string]any); ok {
			if rcText := asString(delta["reasoning_content"]); rcText != "" {
				events = append(events, StreamEvent{Kind: EventThinkingDelta, Text: rcText})
			}
			if txt := asString(delta["content"]); txt != "" {
				events = append(events, StreamEvent{Kind: EventTextDelta, Text: txt})
			}
			if tcs, ok := delta["tool_calls"].([]any); ok {
				for _, rtc := range tcs {
					tc, ok := rtc.(map[string]any)
					if !ok {
						continue
					}
					idx := asInt(tc["index"])
					id := asString(tc["id"])
					fn, _ := tc["function"].(map[string]any)
					name := asString(fn["name"])
					args := asString(fn["arguments"])
					if id != "" || name != "" {
						events = append(events, StreamEvent{
							Kind:      EventToolStart,
							ToolIndex: idx,
							ToolID:    id,
							ToolName:  name,
						})
					}
					if args != "" {
						events = append(events, StreamEvent{
							Kind:      EventToolDelta,
							ToolIndex: idx,
							ToolArgs:  args,
						})
					}
				}
			}
		}
		if fr := asString(cm["finish_reason"]); fr != "" {
			events = append(events, StreamEvent{
				Kind:         EventFinish,
				FinishReason: normalizeFinishReason(fr),
			})
		}
	}
	return events
}

func (st *StreamTranslator) parseAnthropicEvent(obj map[string]any) []StreamEvent {
	var events []StreamEvent
	typ := asString(obj["type"])
	switch typ {
	case "message_start":
		st.started = true
		var u *Usage
		if msg, ok := obj["message"].(map[string]any); ok {
			if um, ok := msg["usage"].(map[string]any); ok {
				u = &Usage{InputTokens: asInt64(um["input_tokens"])}
			}
		}
		events = append(events, StreamEvent{Kind: EventStart, ID: st.msgID, Model: st.Model, Usage: u})
	case "content_block_start":
		idx := asInt(obj["index"])
		if cb, ok := obj["content_block"].(map[string]any); ok {
			cbType := asString(cb["type"])
			st.anthropicIdx[idx] = cbType
			if cbType == "tool_use" {
				events = append(events, StreamEvent{
					Kind:      EventToolStart,
					ToolIndex: idx,
					ToolID:    asString(cb["id"]),
					ToolName:  asString(cb["name"]),
				})
			}
		}
	case "content_block_delta":
		idx := asInt(obj["index"])
		if delta, ok := obj["delta"].(map[string]any); ok {
			switch asString(delta["type"]) {
			case "text_delta":
				if txt := asString(delta["text"]); txt != "" {
					events = append(events, StreamEvent{Kind: EventTextDelta, Text: txt})
				}
			case "thinking_delta":
				if txt := asString(delta["thinking"]); txt != "" {
					events = append(events, StreamEvent{Kind: EventThinkingDelta, Text: txt})
				}
			case "input_json_delta":
				if pj := asString(delta["partial_json"]); pj != "" {
					events = append(events, StreamEvent{Kind: EventToolDelta, ToolIndex: idx, ToolArgs: pj})
				}
			}
		}
	case "message_delta":
		var u *Usage
		if um, ok := obj["usage"].(map[string]any); ok {
			u = &Usage{OutputTokens: asInt64(um["output_tokens"])}
		}
		fr := ""
		if delta, ok := obj["delta"].(map[string]any); ok {
			if sr := asString(delta["stop_reason"]); sr != "" {
				fr = normalizeFinishReason(sr)
			}
		}
		events = append(events, StreamEvent{Kind: EventFinish, FinishReason: fr, Usage: u})
	case "message_stop":
		events = append(events, StreamEvent{Kind: EventFinish, FinishReason: "stop"})
	}
	return events
}

func (st *StreamTranslator) parseResponsesEvent(obj map[string]any) []StreamEvent {
	var events []StreamEvent
	typ := asString(obj["type"])
	switch typ {
	case "response.created":
		if !st.started {
			st.started = true
			events = append(events, StreamEvent{Kind: EventStart, ID: st.msgID, Model: st.Model})
		}
	case "response.output_text.delta":
		if !st.started {
			st.started = true
			events = append(events, StreamEvent{Kind: EventStart, ID: st.msgID, Model: st.Model})
		}
		if d := asString(obj["delta"]); d != "" {
			events = append(events, StreamEvent{Kind: EventTextDelta, Text: d})
		}
	case "response.output_item.added":
		if item, ok := obj["item"].(map[string]any); ok && asString(item["type"]) == "function_call" {
			events = append(events, StreamEvent{
				Kind:      EventToolStart,
				ToolIndex: asInt(obj["output_index"]),
				ToolID:    asString(item["call_id"]),
				ToolName:  asString(item["name"]),
			})
		}
	case "response.function_call_arguments.delta":
		if d := asString(obj["delta"]); d != "" {
			events = append(events, StreamEvent{
				Kind:      EventToolDelta,
				ToolIndex: asInt(obj["output_index"]),
				ToolArgs:  d,
			})
		}
	case "response.completed":
		var u *Usage
		if resp, ok := obj["response"].(map[string]any); ok {
			if um, ok := resp["usage"].(map[string]any); ok {
				u = &Usage{
					InputTokens:  asInt64(um["input_tokens"]),
					OutputTokens: asInt64(um["output_tokens"]),
					TotalTokens:  asInt64(um["total_tokens"]),
				}
			}
		}
		events = append(events, StreamEvent{Kind: EventFinish, FinishReason: "stop", Usage: u})
	}
	return events
}

func (st *StreamTranslator) parseGeminiEvent(obj map[string]any) []StreamEvent {
	var events []StreamEvent
	if !st.started {
		st.started = true
		events = append(events, StreamEvent{Kind: EventStart, ID: st.msgID, Model: st.Model})
	}
	if um, ok := obj["usageMetadata"].(map[string]any); ok {
		inTok := asInt64(um["promptTokenCount"])
		outTok := asInt64(um["candidatesTokenCount"])
		tot := asInt64(um["totalTokenCount"])
		if tot == 0 {
			tot = inTok + outTok
		}
		events = append(events, StreamEvent{
			Kind:  EventFinish,
			Usage: &Usage{InputTokens: inTok, OutputTokens: outTok, TotalTokens: tot},
		})
	}
	if cands, ok := obj["candidates"].([]any); ok {
		for _, rc := range cands {
			cm, ok := rc.(map[string]any)
			if !ok {
				continue
			}
			if content, ok := cm["content"].(map[string]any); ok {
				if parts, ok := content["parts"].([]any); ok {
					for idx, rp := range parts {
						pm, ok := rp.(map[string]any)
						if !ok {
							continue
						}
						if txt := asString(pm["text"]); txt != "" {
							if thought, _ := pm["thought"].(bool); thought {
								events = append(events, StreamEvent{Kind: EventThinkingDelta, Text: txt})
							} else {
								events = append(events, StreamEvent{Kind: EventTextDelta, Text: txt})
							}
						} else if fc, ok := pm["functionCall"].(map[string]any); ok {
							argsBytes, _ := json.Marshal(fc["args"])
							events = append(events,
								StreamEvent{Kind: EventToolStart, ToolIndex: idx, ToolID: "call_" + asString(fc["name"]), ToolName: asString(fc["name"])},
								StreamEvent{Kind: EventToolDelta, ToolIndex: idx, ToolArgs: string(argsBytes)},
							)
						}
					}
				}
			}
			if fr := asString(cm["finishReason"]); fr != "" {
				events = append(events, StreamEvent{Kind: EventFinish, FinishReason: normalizeFinishReason(fr)})
			}
		}
	}
	return events
}

func (st *StreamTranslator) parseOllamaLine(line string) []StreamEvent {
	var obj map[string]any
	if err := json.Unmarshal([]byte(line), &obj); err != nil {
		return nil
	}
	var events []StreamEvent
	if !st.started {
		st.started = true
		events = append(events, StreamEvent{Kind: EventStart, ID: st.msgID, Model: st.Model})
	}
	if msg, ok := obj["message"].(map[string]any); ok {
		if txt := asString(msg["content"]); txt != "" {
			events = append(events, StreamEvent{Kind: EventTextDelta, Text: txt})
		}
	}
	if done, _ := obj["done"].(bool); done {
		u := &Usage{
			InputTokens:  asInt64(obj["prompt_eval_count"]),
			OutputTokens: asInt64(obj["eval_count"]),
		}
		u.TotalTokens = u.InputTokens + u.OutputTokens
		events = append(events, StreamEvent{Kind: EventFinish, FinishReason: "stop", Usage: u})
	}
	return events
}

func (st *StreamTranslator) encodeEvent(ev StreamEvent) []byte {
	switch st.ToProto {
	case types.ProtocolOpenAI:
		return st.encodeOpenAIEvent(ev)
	case types.ProtocolAnthropic:
		return st.encodeAnthropicEvent(ev)
	case types.ProtocolResponses:
		return st.encodeResponsesEvent(ev)
	case types.ProtocolGemini:
		return st.encodeGeminiEvent(ev)
	case types.ProtocolOllama:
		return st.encodeOllamaEvent(ev)
	default:
		return st.encodeOpenAIEvent(ev)
	}
}

func sseLine(event string, data any) []byte {
	b, _ := json.Marshal(data)
	if event != "" {
		return []byte("event: " + event + "\ndata: " + string(b) + "\n\n")
	}
	return []byte("data: " + string(b) + "\n\n")
}

func (st *StreamTranslator) encodeOpenAIEvent(ev StreamEvent) []byte {
	base := func(delta map[string]any, finish any) []byte {
		payload := map[string]any{
			"id":      st.msgID,
			"object":  "chat.completion.chunk",
			"created": time.Now().Unix(),
			"model":   st.Model,
			"choices": []map[string]any{{
				"index":         0,
				"delta":         delta,
				"finish_reason": finish,
			}},
		}
		return sseLine("", payload)
	}
	switch ev.Kind {
	case EventStart:
		return base(map[string]any{"role": "assistant", "content": ""}, nil)
	case EventTextDelta:
		return base(map[string]any{"content": ev.Text}, nil)
	case EventThinkingDelta:
		return base(map[string]any{"reasoning_content": ev.Text}, nil)
	case EventToolStart:
		return base(map[string]any{
			"tool_calls": []map[string]any{{
				"index": ev.ToolIndex,
				"id":    ev.ToolID,
				"type":  "function",
				"function": map[string]any{
					"name":      ev.ToolName,
					"arguments": "",
				},
			}},
		}, nil)
	case EventToolDelta:
		return base(map[string]any{
			"tool_calls": []map[string]any{{
				"index":    ev.ToolIndex,
				"function": map[string]any{"arguments": ev.ToolArgs},
			}},
		}, nil)
	case EventFinish:
		var buf bytes.Buffer
		if ev.FinishReason != "" {
			buf.Write(base(map[string]any{}, ev.FinishReason))
		}
		if ev.Usage != nil && (ev.Usage.InputTokens > 0 || ev.Usage.OutputTokens > 0) {
			uChunk, _ := json.Marshal(map[string]any{
				"id":      st.msgID,
				"object":  "chat.completion.chunk",
				"created": time.Now().Unix(),
				"model":   st.Model,
				"choices": []any{},
				"usage": map[string]any{
					"prompt_tokens":     ev.Usage.InputTokens,
					"completion_tokens": ev.Usage.OutputTokens,
					"total_tokens":      ev.Usage.TotalTokens,
				},
			})
			buf.WriteString("data: " + string(uChunk) + "\n\n")
		}
		if ev.FinishReason == "stop" || ev.FinishReason == "tool_calls" || ev.FinishReason == "length" {
			buf.WriteString("data: [DONE]\n\n")
		}
		return buf.Bytes()
	}
	return nil
}

func (st *StreamTranslator) encodeAnthropicEvent(ev StreamEvent) []byte {
	switch ev.Kind {
	case EventStart:
		return sseLine("message_start", map[string]any{
			"type": "message_start",
			"message": map[string]any{
				"id":      st.msgID,
				"type":    "message",
				"role":    "assistant",
				"model":   st.Model,
				"content": []any{},
				"usage": map[string]any{
					"input_tokens":  st.Usage.InputTokens,
					"output_tokens": 0,
				},
			},
		})
	case EventTextDelta:
		var buf bytes.Buffer
		if !st.textBlockOpen {
			st.textBlockOpen = true
			buf.Write(sseLine("content_block_start", map[string]any{
				"type":          "content_block_start",
				"index":         st.nextBlockIdx,
				"content_block": map[string]any{"type": "text", "text": ""},
			}))
		}
		buf.Write(sseLine("content_block_delta", map[string]any{
			"type":  "content_block_delta",
			"index": st.nextBlockIdx,
			"delta": map[string]any{"type": "text_delta", "text": ev.Text},
		}))
		return buf.Bytes()
	case EventToolStart:
		var buf bytes.Buffer
		if st.textBlockOpen {
			buf.Write(sseLine("content_block_stop", map[string]any{"type": "content_block_stop", "index": st.nextBlockIdx}))
			st.textBlockOpen = false
			st.nextBlockIdx++
		}
		idx := st.nextBlockIdx
		st.nextBlockIdx++
		st.toolBlocks[ev.ToolIndex] = idx
		id := ev.ToolID
		if id == "" {
			id = fmt.Sprintf("toolu_%d", idx)
		}
		buf.Write(sseLine("content_block_start", map[string]any{
			"type":  "content_block_start",
			"index": idx,
			"content_block": map[string]any{
				"type":  "tool_use",
				"id":    id,
				"name":  ev.ToolName,
				"input": map[string]any{},
			},
		}))
		return buf.Bytes()
	case EventToolDelta:
		idx, ok := st.toolBlocks[ev.ToolIndex]
		if !ok {
			idx = st.nextBlockIdx
		}
		return sseLine("content_block_delta", map[string]any{
			"type":  "content_block_delta",
			"index": idx,
			"delta": map[string]any{"type": "input_json_delta", "partial_json": ev.ToolArgs},
		})
	case EventFinish:
		if ev.FinishReason == "" {
			return nil
		}
		var buf bytes.Buffer
		if st.textBlockOpen {
			buf.Write(sseLine("content_block_stop", map[string]any{"type": "content_block_stop", "index": st.nextBlockIdx}))
			st.textBlockOpen = false
			st.nextBlockIdx++
		}
		for _, idx := range st.toolBlocks {
			buf.Write(sseLine("content_block_stop", map[string]any{"type": "content_block_stop", "index": idx}))
		}
		st.toolBlocks = map[int]int{}
		sr := "end_turn"
		if ev.FinishReason == "tool_calls" {
			sr = "tool_use"
		} else if ev.FinishReason == "length" {
			sr = "max_tokens"
		}
		buf.Write(sseLine("message_delta", map[string]any{
			"type":  "message_delta",
			"delta": map[string]any{"stop_reason": sr},
			"usage": map[string]any{"output_tokens": st.Usage.OutputTokens},
		}))
		buf.Write(sseLine("message_stop", map[string]any{"type": "message_stop"}))
		return buf.Bytes()
	}
	return nil
}

func (st *StreamTranslator) encodeResponsesEvent(ev StreamEvent) []byte {
	switch ev.Kind {
	case EventStart:
		return sseLine("response.created", map[string]any{
			"type": "response.created",
			"response": map[string]any{
				"id":     st.msgID,
				"object": "response",
				"model":  st.Model,
				"status": "in_progress",
			},
		})
	case EventTextDelta:
		return sseLine("response.output_text.delta", map[string]any{
			"type":  "response.output_text.delta",
			"delta": ev.Text,
		})
	case EventToolStart:
		return sseLine("response.output_item.added", map[string]any{
			"type":         "response.output_item.added",
			"output_index": ev.ToolIndex,
			"item": map[string]any{
				"type":    "function_call",
				"call_id": ev.ToolID,
				"name":    ev.ToolName,
			},
		})
	case EventToolDelta:
		return sseLine("response.function_call_arguments.delta", map[string]any{
			"type":         "response.function_call_arguments.delta",
			"output_index": ev.ToolIndex,
			"delta":        ev.ToolArgs,
		})
	case EventFinish:
		if ev.FinishReason == "" {
			return nil
		}
		return sseLine("response.completed", map[string]any{
			"type": "response.completed",
			"response": map[string]any{
				"id":     st.msgID,
				"object": "response",
				"model":  st.Model,
				"status": "completed",
				"usage": map[string]any{
					"input_tokens":  st.Usage.InputTokens,
					"output_tokens": st.Usage.OutputTokens,
					"total_tokens":  st.Usage.TotalTokens,
				},
			},
		})
	}
	return nil
}

func (st *StreamTranslator) encodeGeminiEvent(ev StreamEvent) []byte {
	switch ev.Kind {
	case EventTextDelta:
		return sseLine("", map[string]any{
			"candidates": []map[string]any{{
				"index": 0,
				"content": map[string]any{
					"role":  "model",
					"parts": []map[string]any{{"text": ev.Text}},
				},
			}},
		})
	case EventFinish:
		if ev.FinishReason == "" && ev.Usage == nil {
			return nil
		}
		return sseLine("", map[string]any{
			"candidates": []map[string]any{{
				"index":        0,
				"finishReason": "STOP",
				"content":      map[string]any{"role": "model", "parts": []any{}},
			}},
			"usageMetadata": map[string]any{
				"promptTokenCount":     st.Usage.InputTokens,
				"candidatesTokenCount": st.Usage.OutputTokens,
				"totalTokenCount":      st.Usage.TotalTokens,
			},
		})
	}
	return nil
}

func (st *StreamTranslator) encodeOllamaEvent(ev StreamEvent) []byte {
	switch ev.Kind {
	case EventTextDelta:
		b, _ := json.Marshal(map[string]any{
			"model":   st.Model,
			"message": map[string]any{"role": "assistant", "content": ev.Text},
			"done":    false,
		})
		return append(b, '\n')
	case EventFinish:
		if ev.FinishReason == "" {
			return nil
		}
		b, _ := json.Marshal(map[string]any{
			"model":             st.Model,
			"message":           map[string]any{"role": "assistant", "content": ""},
			"done":              true,
			"prompt_eval_count": st.Usage.InputTokens,
			"eval_count":        st.Usage.OutputTokens,
		})
		return append(b, '\n')
	}
	return nil
}

// UsageSniffer passively inspects pass-through SSE chunks for token usage without modifying bytes.
type UsageSniffer struct {
	proto types.Protocol
	buf   bytes.Buffer
	Usage Usage
}

func NewUsageSniffer(proto types.Protocol) *UsageSniffer {
	return &UsageSniffer{proto: proto}
}

func (us *UsageSniffer) Feed(chunk []byte) {
	us.buf.Write(chunk)
	data := us.buf.Bytes()
	st := &StreamTranslator{FromProto: us.proto}
	for {
		idx := bytes.IndexByte(data, '\n')
		if idx < 0 {
			break
		}
		line := strings.TrimRight(string(data[:idx+1]), "\r\n")
		data = data[idx+1:]
		for _, ev := range st.parseLine(line) {
			if ev.Usage != nil {
				if ev.Usage.InputTokens > 0 {
					us.Usage.InputTokens = ev.Usage.InputTokens
				}
				if ev.Usage.OutputTokens > 0 {
					us.Usage.OutputTokens = ev.Usage.OutputTokens
				}
				if ev.Usage.TotalTokens > 0 {
					us.Usage.TotalTokens = ev.Usage.TotalTokens
				} else {
					us.Usage.TotalTokens = us.Usage.InputTokens + us.Usage.OutputTokens
				}
			}
		}
	}
	us.buf.Reset()
	us.buf.Write(data)
}

type collectedTool struct {
	index int
	id    string
	name  string
	args  strings.Builder
}

// StreamCollector incrementally accumulates upstream stream events into a CanonicalResponse.
type StreamCollector struct {
	tr            *StreamTranslator
	fallbackModel string
	id            string
	model         string
	finishReason  string
	usage         Usage
	text          strings.Builder
	thinking      strings.Builder
	tools         map[int]*collectedTool
	toolOrder     []int
	seenEvents    int
}

// NewStreamCollector creates a collector that parses fromProto SSE/NDJSON into CanonicalResponse.
func NewStreamCollector(fromProto types.Protocol, fallbackModel string) *StreamCollector {
	return &StreamCollector{
		tr:            NewStreamTranslator(fromProto, types.ProtocolOpenAI, fallbackModel),
		fallbackModel: fallbackModel,
		tools:         make(map[int]*collectedTool),
	}
}

func (sc *StreamCollector) applyEvent(ev StreamEvent) {
	sc.seenEvents++
	if ev.ID != "" && sc.id == "" {
		sc.id = ev.ID
	}
	if ev.Model != "" {
		sc.model = ev.Model
	}
	if ev.Usage != nil {
		if ev.Usage.InputTokens > 0 {
			sc.usage.InputTokens = ev.Usage.InputTokens
		}
		if ev.Usage.OutputTokens > 0 {
			sc.usage.OutputTokens = ev.Usage.OutputTokens
		}
		if ev.Usage.TotalTokens > 0 {
			sc.usage.TotalTokens = ev.Usage.TotalTokens
		} else {
			sc.usage.TotalTokens = sc.usage.InputTokens + sc.usage.OutputTokens
		}
	}
	switch ev.Kind {
	case EventTextDelta:
		sc.text.WriteString(ev.Text)
	case EventThinkingDelta:
		sc.thinking.WriteString(ev.Text)
	case EventToolStart:
		t := sc.ensureTool(ev.ToolIndex)
		if ev.ToolID != "" {
			t.id = ev.ToolID
		}
		if ev.ToolName != "" {
			t.name = ev.ToolName
		}
	case EventToolDelta:
		t := sc.ensureTool(ev.ToolIndex)
		if ev.ToolArgs != "" {
			t.args.WriteString(ev.ToolArgs)
		}
	case EventFinish:
		if ev.FinishReason != "" && (sc.finishReason == "" || sc.finishReason == "stop") {
			sc.finishReason = ev.FinishReason
		}
	}
}

func (sc *StreamCollector) ensureTool(idx int) *collectedTool {
	if t, ok := sc.tools[idx]; ok {
		return t
	}
	t := &collectedTool{index: idx}
	sc.tools[idx] = t
	sc.toolOrder = append(sc.toolOrder, idx)
	return t
}

// Feed consumes raw stream bytes incrementally.
func (sc *StreamCollector) Feed(chunk []byte) {
	sc.tr.buf.Write(chunk)
	data := sc.tr.buf.Bytes()
	for {
		idx := bytes.IndexByte(data, '\n')
		if idx < 0 {
			break
		}
		line := strings.TrimRight(string(data[:idx+1]), "\r\n")
		data = data[idx+1:]
		for _, ev := range sc.tr.parseLine(line) {
			sc.applyEvent(ev)
		}
	}
	sc.tr.buf.Reset()
	sc.tr.buf.Write(data)
}

// Result finalizes any buffered tail and builds the CanonicalResponse.
func (sc *StreamCollector) Result() (*CanonicalResponse, error) {
	if sc.tr.buf.Len() > 0 {
		line := strings.TrimRight(sc.tr.buf.String(), "\r\n")
		sc.tr.buf.Reset()
		for _, ev := range sc.tr.parseLine(line) {
			sc.applyEvent(ev)
		}
	}
	if sc.seenEvents == 0 {
		return nil, fmt.Errorf("no stream events parsed")
	}

	model := sc.model
	if model == "" {
		model = sc.fallbackModel
	}
	parts := make([]ContentPart, 0, 2+len(sc.toolOrder))
	if sc.thinking.Len() > 0 {
		parts = append(parts, ContentPart{Type: "thinking", Text: sc.thinking.String()})
	}
	if sc.text.Len() > 0 || len(sc.toolOrder) == 0 {
		parts = append(parts, ContentPart{Type: "text", Text: sc.text.String()})
	}
	for _, idx := range sc.toolOrder {
		t := sc.tools[idx]
		rawArgs := strings.TrimSpace(t.args.String())
		var parsed any
		if rawArgs != "" {
			if err := json.Unmarshal([]byte(rawArgs), &parsed); err != nil {
				parsed = map[string]any{"_raw": rawArgs}
			}
		} else {
			parsed = map[string]any{}
		}
		parts = append(parts, ContentPart{
			Type:      "tool_use",
			ToolID:    t.id,
			ToolName:  t.name,
			ToolInput: parsed,
		})
	}
	finish := sc.finishReason
	if finish == "" {
		if len(sc.toolOrder) > 0 {
			finish = "tool_calls"
		} else {
			finish = "stop"
		}
	}
	if sc.usage.TotalTokens == 0 {
		sc.usage.TotalTokens = sc.usage.InputTokens + sc.usage.OutputTokens
	}
	return &CanonicalResponse{
		ID:           sc.id,
		Model:        model,
		Parts:        parts,
		FinishReason: finish,
		Usage:        sc.usage,
	}, nil
}

// CollectStreamToCanonical folds an entire SSE/NDJSON response stream into a single CanonicalResponse.
func CollectStreamToCanonical(fromProto types.Protocol, streamBytes []byte, fallbackModel string) (*CanonicalResponse, error) {
	sc := NewStreamCollector(fromProto, fallbackModel)
	sc.Feed(streamBytes)
	return sc.Result()
}
