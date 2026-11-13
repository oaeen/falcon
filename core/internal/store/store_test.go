package store

import (
	"fmt"
	"testing"

	"github.com/falcon-gateway/falcon/core/internal/types"
)

func TestStorePersistenceAndLogCap(t *testing.T) {
	dir := t.TempDir()
	st, err := Open(dir)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}

	// Default settings
	cfg := st.ConfigSnapshot()
	if cfg.Settings.Port != 18787 || !cfg.Settings.AllowLocalKeyless || !cfg.Settings.ChinaMirror {
		t.Fatalf("unexpected default settings: %+v", cfg.Settings)
	}

	// Update settings
	newPort := 19000
	lan := true
	updated, relisten, err := st.UpdateSettings(types.SettingsPatch{Port: &newPort, LanEnabled: &lan})
	if err != nil || !relisten || updated.Port != 19000 || !updated.LanEnabled {
		t.Fatalf("UpdateSettings failed: %+v relisten=%v err=%v", updated, relisten, err)
	}

	// Create key + rotate
	k, created, err := st.CreateOrUpdateKey(types.AccessKey{Name: "TestKey", Enabled: true})
	if err != nil || !created || k.Secret == "" {
		t.Fatalf("CreateOrUpdateKey failed: %+v created=%v err=%v", k, created, err)
	}
	rot, err := st.RotateKey(k.ID)
	if err != nil || rot.Secret == k.Secret {
		t.Fatalf("RotateKey failed: %v", err)
	}

	// Cap logs at 500
	for i := 0; i < 550; i++ {
		st.RecordRequest(types.RequestLogEntry{
			ID:         fmt.Sprintf("req-%d", i),
			StatusCode: 200,
			KeyID:      k.ID,
		}, map[string]int{"API_KEY": 1})
	}
	logs := st.GetLogs(0)
	if len(logs) != MaxLogEntries {
		t.Fatalf("expected %d logs, got %d", MaxLogEntries, len(logs))
	}
	if logs[0].ID != "req-549" {
		t.Fatalf("expected newest log first, got %s", logs[0].ID)
	}

	// Re-open from disk
	st2, err := Open(dir)
	if err != nil {
		t.Fatalf("re-Open: %v", err)
	}
	if st2.Settings().Port != 19000 {
		t.Fatalf("persisted port mismatch: %d", st2.Settings().Port)
	}
	if len(st2.GetLogs(1000)) != MaxLogEntries {
		t.Fatalf("persisted log count mismatch: %d", len(st2.GetLogs(1000)))
	}
	if st2.RedactSummary().TotalHits != 550 {
		t.Fatalf("expected 550 redact hits, got %d", st2.RedactSummary().TotalHits)
	}
}
