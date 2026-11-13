package redact

import (
	"strings"
	"testing"

	"github.com/falcon-gateway/falcon/core/internal/types"
)

func TestRedactAndRestoreAcrossSSEChunks(t *testing.T) {
	settings := types.DefaultSettings()
	settings.RedactEnabled = true
	settings.RedactRestore = true
	settings.RedactAllow = []string{"public@example.com"}
	settings.RedactRules = []types.RedactRule{
		{ID: "r1", Name: "PROJECT_CODE", Pattern: `PROJ-\d{4}`, Placeholder: "PROJ", Enabled: true},
	}

	sess := NewSession(settings)
	prompt := "Key: sk-1234567890abcdef1234567890 email: alice@secret.org allowed: public@example.com code: PROJ-9001 sameKey: sk-1234567890abcdef1234567890"
	masked := sess.MaskText(prompt)

	if strings.Contains(masked, "sk-1234567890abcdef1234567890") {
		t.Fatalf("API key was not redacted: %s", masked)
	}
	if strings.Contains(masked, "alice@secret.org") {
		t.Fatalf("email was not redacted: %s", masked)
	}
	if !strings.Contains(masked, "public@example.com") {
		t.Fatalf("allowlisted email should not be redacted: %s", masked)
	}
	if strings.Contains(masked, "PROJ-9001") {
		t.Fatalf("custom rule was not redacted: %s", masked)
	}
	// Deterministic placeholder reused for duplicate key
	if strings.Count(masked, "[REDACTED_KEY_1]") != 2 {
		t.Fatalf("expected deterministic [REDACTED_KEY_1] twice, got: %s", masked)
	}

	// Simulate SSE response split across TCP chunks AND token deltas
	sr := NewStreamRestorer(sess)
	chunk1 := []byte("data: {\"choices\":[{\"delta\":{\"content\":\"Secret is [RED\"}}]}\n\n")
	chunk2 := []byte("data: {\"choices\":[{\"delta\":{\"content\":\"ACTED_KEY_1] and \"}}]}\n")
	chunk3 := []byte("\ndata: {\"choices\":[{\"delta\":{\"content\":\"[REDACTED_PROJ_1]!\"}}]}\n\n")

	var restored strings.Builder
	restored.Write(sr.ProcessChunk(chunk1))
	restored.Write(sr.ProcessChunk(chunk2))
	restored.Write(sr.ProcessChunk(chunk3))
	restored.Write(sr.Flush())

	full := restored.String()
	if !strings.Contains(full, "sk-1234567890abcdef1234567890") {
		t.Fatalf("SSE stream failed to restore split KEY placeholder: %s", full)
	}
	if !strings.Contains(full, "PROJ-9001!") {
		t.Fatalf("SSE stream failed to restore custom PROJ placeholder: %s", full)
	}
}

func TestPreview(t *testing.T) {
	settings := types.DefaultSettings()
	res := Preview(settings, "token ghp_abcdefghijklmnopqrstuvwxyz123456 ip 10.0.0.5 phone +86 13800138000")
	if res.TotalHits != 3 {
		t.Fatalf("expected 3 hits, got %d (%+v)", res.TotalHits, res)
	}
	if strings.Contains(res.MaskedText, "13800138000") {
		t.Fatalf("phone not masked: %s", res.MaskedText)
	}
}
