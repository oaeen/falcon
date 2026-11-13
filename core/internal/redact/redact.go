package redact

import (
	"bytes"
	"encoding/json"
	"fmt"
	"regexp"
	"sort"
	"strings"

	"github.com/falcon-gateway/falcon/core/internal/types"
)

// Hit describes one redaction match for preview/telemetry.
type Hit struct {
	Kind        string `json:"kind"`
	RuleName    string `json:"ruleName,omitempty"`
	Category    string `json:"category,omitempty"`
	Placeholder string `json:"placeholder"`
	Count       int    `json:"count"`
}

// BuiltinRuleCount returns the number of built-in secret/PII detection rules.
func BuiltinRuleCount() int {
	return len(builtinRules)
}

// PreviewResult is returned by Preview(text).
type PreviewResult struct {
	MaskedText string `json:"maskedText"`
	Hits       []Hit  `json:"hits"`
	TotalHits  int    `json:"totalHits"`
}

type builtinRule struct {
	kind        string
	placeholder string
	re          *regexp.Regexp
	group       int // capture group index (0 = whole match)
}

var builtinRules = []builtinRule{
	{
		kind:        "PEM_KEY",
		placeholder: "PEM",
		re:          regexp.MustCompile(`-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY(?: BLOCK)?-----[\s\S]+?-----END (?:[A-Z0-9]+ )*PRIVATE KEY(?: BLOCK)?-----`),
	},
	{
		kind:        "API_KEY",
		placeholder: "KEY",
		re:          regexp.MustCompile(`\b(?:sk-(?:ant-|proj-|or-|svcacct-|admin-|flc-)?[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,}|glpat-[A-Za-z0-9_-]{16,}|AIza[0-9A-Za-z_-]{30,}|xox[abposr]-[0-9A-Za-z-]{10,}|(?:AKIA|ASIA)[0-9A-Z]{16}|hf_[A-Za-z0-9]{20,}|gsk_[A-Za-z0-9]{20,}|xai-[A-Za-z0-9]{20,}|ark-[A-Za-z0-9_-]{16,})\b`),
	},
	{
		kind:        "JWT_TOKEN",
		placeholder: "TOKEN",
		re:          regexp.MustCompile(`\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b`),
	},
	{
		kind:        "BEARER_TOKEN",
		placeholder: "TOKEN",
		re:          regexp.MustCompile(`(?i)\bBearer\s+([A-Za-z0-9._~+/=-]{16,})`),
		group:       1,
	},
	{
		kind:        "EMAIL",
		placeholder: "EMAIL",
		re:          regexp.MustCompile(`\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b`),
	},
	{
		kind:        "PHONE",
		placeholder: "PHONE",
		// Mainland China 11-digit mobile or +country international phone
		re: regexp.MustCompile(`(?:\+?86[-\s]?)?1[3-9]\d{9}\b|\+[1-9]\d{0,2}[-\s]?\d{2,4}[-\s]?\d{3,4}[-\s]?\d{3,4}\b`),
	},
	{
		kind:        "IPV4",
		placeholder: "IP",
		re:          regexp.MustCompile(`\b(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\b`),
	},
}

var placeholderPattern = regexp.MustCompile(`\[REDACTED_[A-Z0-9_]+_\d+\]`)

// Session maintains deterministic placeholder<->secret mappings for a single request/response lifecycle.
type Session struct {
	enabled     bool
	restore     bool
	allowSet    map[string]struct{}
	customRules []compiledCustomRule
	valToPh     map[string]string // original -> placeholder
	phToVal     map[string]string // placeholder -> original
	counters    map[string]int    // placeholder prefix -> next index
	hitCounts   map[string]int    // kind -> hits
}

type compiledCustomRule struct {
	kind        string
	placeholder string
	re          *regexp.Regexp
}

// NewSession builds a redaction session from gateway Settings.
func NewSession(settings types.Settings) *Session {
	s := &Session{
		enabled:   settings.RedactEnabled,
		restore:   settings.RedactRestore,
		allowSet:  make(map[string]struct{}, len(settings.RedactAllow)),
		valToPh:   make(map[string]string),
		phToVal:   make(map[string]string),
		counters:  make(map[string]int),
		hitCounts: make(map[string]int),
	}
	for _, a := range settings.RedactAllow {
		a = strings.TrimSpace(a)
		if a != "" {
			s.allowSet[strings.ToLower(a)] = struct{}{}
		}
	}
	for _, r := range settings.RedactRules {
		if !r.Enabled || strings.TrimSpace(r.Pattern) == "" {
			continue
		}
		re, err := regexp.Compile(r.Pattern)
		if err != nil {
			continue
		}
		rawPh := r.Replacement
		if rawPh == "" {
			rawPh = r.Placeholder
		}
		ph := strings.ToUpper(strings.TrimSpace(rawPh))
		if ph == "" {
			ph = "CUSTOM"
		}
		ph = sanitizePlaceholderPrefix(ph)
		kind := strings.TrimSpace(r.Name)
		if kind == "" {
			kind = "CUSTOM"
		}
		s.customRules = append(s.customRules, compiledCustomRule{
			kind:        kind,
			placeholder: ph,
			re:          re,
		})
	}
	return s
}

func sanitizePlaceholderPrefix(s string) string {
	var b strings.Builder
	for _, ch := range s {
		if (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_' {
			b.WriteRune(ch)
		}
	}
	if b.Len() == 0 {
		return "CUSTOM"
	}
	return b.String()
}

func (s *Session) isAllowed(val string) bool {
	if _, ok := s.allowSet[strings.ToLower(strings.TrimSpace(val))]; ok {
		return true
	}
	// Do not re-mask an existing placeholder
	if placeholderPattern.MatchString(val) {
		return true
	}
	return false
}

func (s *Session) placeholderFor(val, kind, phPrefix string) string {
	if ph, ok := s.valToPh[val]; ok {
		s.hitCounts[kind]++
		return ph
	}
	s.counters[phPrefix]++
	ph := fmt.Sprintf("[REDACTED_%s_%d]", phPrefix, s.counters[phPrefix])
	s.valToPh[val] = ph
	s.phToVal[ph] = val
	s.hitCounts[kind]++
	return ph
}

// MaskText scans and masks sensitive spans in plain text.
func (s *Session) MaskText(text string) string {
	if !s.enabled || text == "" {
		return text
	}
	type span struct {
		start int
		end   int
		val   string
		kind  string
		ph    string
	}
	var spans []span

	collect := func(re *regexp.Regexp, group int, kind, ph string) {
		matches := re.FindAllStringSubmatchIndex(text, -1)
		for _, m := range matches {
			a, b := m[0], m[1]
			if group > 0 && len(m) >= 2*(group+1) && m[2*group] >= 0 {
				a, b = m[2*group], m[2*group+1]
			}
			if a >= b {
				continue
			}
			val := text[a:b]
			if s.isAllowed(val) {
				continue
			}
			spans = append(spans, span{start: a, end: b, val: val, kind: kind, ph: ph})
		}
	}

	// Custom rules first so user rules take precedence on overlaps
	for _, cr := range s.customRules {
		collect(cr.re, 0, cr.kind, cr.placeholder)
	}
	for _, br := range builtinRules {
		collect(br.re, br.group, br.kind, br.placeholder)
	}

	if len(spans) == 0 {
		return text
	}

	// Sort by start ascending, longer span first on tie
	sort.Slice(spans, func(i, j int) bool {
		if spans[i].start != spans[j].start {
			return spans[i].start < spans[j].start
		}
		return (spans[i].end - spans[i].start) > (spans[j].end - spans[j].start)
	})

	var out strings.Builder
	cursor := 0
	for _, sp := range spans {
		if sp.start < cursor {
			continue
		}
		out.WriteString(text[cursor:sp.start])
		out.WriteString(s.placeholderFor(sp.val, sp.kind, sp.ph))
		cursor = sp.end
	}
	out.WriteString(text[cursor:])
	return out.String()
}

// MaskJSON recursively masks string values inside a JSON payload (such as chat messages/prompts).
// Structural fields like "model", "role", "type", "id" are preserved untouched.
func (s *Session) MaskJSON(raw []byte) []byte {
	if !s.enabled || len(raw) == 0 {
		return raw
	}
	var doc any
	if err := json.Unmarshal(raw, &doc); err != nil {
		return raw
	}
	masked := s.maskValue("", doc)
	out, err := json.Marshal(masked)
	if err != nil {
		return raw
	}
	return out
}

var skipJSONKeys = map[string]bool{
	"model":       true,
	"role":        true,
	"type":        true,
	"id":          true,
	"object":      true,
	"finish_reason": true,
	"stop_reason": true,
	"name":        true,
	"tool_call_id": true,
	"call_id":     true,
}

func (s *Session) maskValue(key string, v any) any {
	switch tv := v.(type) {
	case string:
		if skipJSONKeys[key] {
			return tv
		}
		return s.MaskText(tv)
	case []any:
		for i := range tv {
			tv[i] = s.maskValue(key, tv[i])
		}
		return tv
	case map[string]any:
		for k, val := range tv {
			tv[k] = s.maskValue(k, val)
		}
		return tv
	default:
		return v
	}
}

// RestoreText replaces placeholders in plain text with original values.
func (s *Session) RestoreText(text string) string {
	if !s.restore || len(s.phToVal) == 0 || text == "" {
		return text
	}
	return placeholderPattern.ReplaceAllStringFunc(text, func(ph string) string {
		if orig, ok := s.phToVal[ph]; ok {
			return orig
		}
		return ph
	})
}

// RestoreJSON restores placeholders inside all string fields of a JSON payload.
func (s *Session) RestoreJSON(raw []byte) []byte {
	if !s.restore || len(s.phToVal) == 0 || len(raw) == 0 {
		return raw
	}
	var doc any
	if err := json.Unmarshal(raw, &doc); err != nil {
		return []byte(s.RestoreText(string(raw)))
	}
	restored := s.restoreValue(doc)
	out, err := json.Marshal(restored)
	if err != nil {
		return raw
	}
	return out
}

func (s *Session) restoreValue(v any) any {
	switch tv := v.(type) {
	case string:
		return s.RestoreText(tv)
	case []any:
		for i := range tv {
			tv[i] = s.restoreValue(tv[i])
		}
		return tv
	case map[string]any:
		for k, val := range tv {
			tv[k] = s.restoreValue(val)
		}
		return tv
	default:
		return v
	}
}

// HitsByKind returns a copy of hit counts recorded in this session.
func (s *Session) HitsByKind() map[string]int {
	out := make(map[string]int, len(s.hitCounts))
	for k, v := range s.hitCounts {
		out[k] = v
	}
	return out
}

// TotalHits returns total redaction replacements made in this session.
func (s *Session) TotalHits() int {
	total := 0
	for _, v := range s.hitCounts {
		total += v
	}
	return total
}

// Preview runs redaction on sample text with forced enabled=true and returns maskedText + hits.
func Preview(settings types.Settings, text string) PreviewResult {
	st := settings
	st.RedactEnabled = true
	sess := NewSession(st)
	masked := sess.MaskText(text)
	hits := make([]Hit, 0, len(sess.valToPh))
	for _, ph := range sess.valToPh {
		kind := kindFromPlaceholder(ph)
		hits = append(hits, Hit{
			Kind:        kind,
			RuleName:    kind,
			Category:    kind,
			Placeholder: ph,
			Count:       1,
		})
	}
	sort.Slice(hits, func(i, j int) bool {
		return hits[i].Placeholder < hits[j].Placeholder
	})
	return PreviewResult{
		MaskedText: masked,
		Hits:       hits,
		TotalHits:  sess.TotalHits(),
	}
}

func kindFromPlaceholder(ph string) string {
	trimmed := strings.TrimPrefix(ph, "[REDACTED_")
	trimmed = strings.TrimSuffix(trimmed, "]")
	if idx := strings.LastIndex(trimmed, "_"); idx > 0 {
		return trimmed[:idx]
	}
	return trimmed
}

// StreamRestorer restores placeholders across chunk boundaries in SSE streams,
// handling both TCP-chunk splits and LLM token splits across delta events.
type StreamRestorer struct {
	sess         *Session
	lineBuf      bytes.Buffer
	pendingToken string
}

// NewStreamRestorer creates a chunk-safe SSE restorer for a Session.
func NewStreamRestorer(sess *Session) *StreamRestorer {
	return &StreamRestorer{sess: sess}
}

// ProcessChunk ingests a chunk of SSE bytes and returns restored bytes ready to send downstream.
func (sr *StreamRestorer) ProcessChunk(chunk []byte) []byte {
	if sr.sess == nil || !sr.sess.restore || len(sr.sess.phToVal) == 0 {
		return chunk
	}
	sr.lineBuf.Write(chunk)
	data := sr.lineBuf.Bytes()

	var out bytes.Buffer
	for {
		idx := bytes.IndexByte(data, '\n')
		if idx < 0 {
			break
		}
		line := string(data[:idx+1])
		data = data[idx+1:]
		out.WriteString(sr.processLine(line))
	}
	sr.lineBuf.Reset()
	sr.lineBuf.Write(data)
	return out.Bytes()
}

// Flush drains any remaining buffered bytes at EOF.
func (sr *StreamRestorer) Flush() []byte {
	if sr.sess == nil || !sr.sess.restore || len(sr.sess.phToVal) == 0 {
		return nil
	}
	var out bytes.Buffer
	if sr.pendingToken != "" {
		out.WriteString(sr.sess.RestoreText(sr.pendingToken))
		sr.pendingToken = ""
	}
	if sr.lineBuf.Len() > 0 {
		out.WriteString(sr.processLine(sr.lineBuf.String()))
		sr.lineBuf.Reset()
	}
	return out.Bytes()
}

func (sr *StreamRestorer) processLine(line string) string {
	trimmed := strings.TrimRight(line, "\r\n")
	newline := line[len(trimmed):]
	if !strings.HasPrefix(trimmed, "data:") {
		return line
	}
	payload := strings.TrimSpace(strings.TrimPrefix(trimmed, "data:"))
	if payload == "" || payload == "[DONE]" {
		return line
	}
	var obj map[string]any
	if err := json.Unmarshal([]byte(payload), &obj); err != nil {
		return sr.sess.RestoreText(line)
	}
	// Handle OpenAI chat delta.content, Anthropic delta.text / content_block.text, Gemini candidates text
	changed := sr.walkSSEMap(obj)
	if !changed && sr.pendingToken == "" {
		// Still restore any other fields directly
		restored := sr.sess.restoreValue(obj)
		b, err := json.Marshal(restored)
		if err != nil {
			return sr.sess.RestoreText(line)
		}
		return "data: " + string(b) + newline
	}
	b, err := json.Marshal(obj)
	if err != nil {
		return sr.sess.RestoreText(line)
	}
	return "data: " + string(b) + newline
}

func (sr *StreamRestorer) walkSSEMap(obj map[string]any) bool {
	changed := false
	// OpenAI Chat: choices[].delta.content
	if choices, ok := obj["choices"].([]any); ok {
		for _, c := range choices {
			cm, ok := c.(map[string]any)
			if !ok {
				continue
			}
			if delta, ok := cm["delta"].(map[string]any); ok {
				if txt, ok := delta["content"].(string); ok {
					delta["content"] = sr.processDeltaText(txt)
					changed = true
				}
			}
		}
	}
	// Anthropic Messages: delta.text
	if delta, ok := obj["delta"].(map[string]any); ok {
		if txt, ok := delta["text"].(string); ok {
			delta["text"] = sr.processDeltaText(txt)
			changed = true
		}
	}
	// OpenAI Responses: delta (string)
	if typ, _ := obj["type"].(string); strings.Contains(typ, "delta") {
		if txt, ok := obj["delta"].(string); ok {
			obj["delta"] = sr.processDeltaText(txt)
			changed = true
		}
	}
	// Gemini: candidates[].content.parts[].text
	if cands, ok := obj["candidates"].([]any); ok {
		for _, c := range cands {
			cm, ok := c.(map[string]any)
			if !ok {
				continue
			}
			if content, ok := cm["content"].(map[string]any); ok {
				if parts, ok := content["parts"].([]any); ok {
					for _, p := range parts {
						if pm, ok := p.(map[string]any); ok {
							if txt, ok := pm["text"].(string); ok {
								pm["text"] = sr.processDeltaText(txt)
								changed = true
							}
						}
					}
				}
			}
		}
	}
	return changed
}

func (sr *StreamRestorer) processDeltaText(txt string) string {
	combined := sr.pendingToken + txt
	sr.pendingToken = ""
	restored := sr.sess.RestoreText(combined)
	// Check if restored ends with a partial placeholder like "[" or "[REDACTED_KEY_1"
	if idx := trailingPartialPlaceholder(restored); idx >= 0 {
		sr.pendingToken = restored[idx:]
		return restored[:idx]
	}
	return restored
}

const partialPrefix = "[REDACTED_"

func trailingPartialPlaceholder(s string) int {
	lastOpen := strings.LastIndexByte(s, '[')
	if lastOpen < 0 {
		return -1
	}
	tail := s[lastOpen:]
	if strings.ContainsRune(tail, ']') {
		return -1
	}
	if len(tail) > 48 {
		return -1
	}
	if len(tail) <= len(partialPrefix) {
		if strings.HasPrefix(partialPrefix, tail) {
			return lastOpen
		}
		return -1
	}
	if strings.HasPrefix(tail, partialPrefix) {
		// Ensure all characters after prefix are valid placeholder chars [A-Z0-9_]
		for i := len(partialPrefix); i < len(tail); i++ {
			c := tail[i]
			if !((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_') {
				return -1
			}
		}
		return lastOpen
	}
	return -1
}
