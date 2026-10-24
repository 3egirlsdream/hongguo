package core

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPlaybackDiagnosticRedactionAndPersistence(t *testing.T) {
	directory := t.TempDir()
	d := &Downloader{diagnostics: newDiagnosticLog(directory)}
	d.recordDiagnostic(diagnosticEvent{Event: "playback_timing", TraceID: "trace-test", Stage: "resolve", Message: "HTTP 403 https://cdn.test/private.mp4?token=secret decryption_key=private-key"})
	data, err := os.ReadFile(filepath.Join(directory, "logs", "app.log"))
	if err != nil {
		t.Fatal(err)
	}
	text := string(data)
	for _, secret := range []string{"private.mp4", "secret", "private-key", "https://"} {
		if strings.Contains(text, secret) {
			t.Fatalf("diagnostic leaked %s", secret)
		}
	}
	for _, field := range []string{"trace-test", "resolve", "HTTP 403", "cdn.test"} {
		if !strings.Contains(text, field) {
			t.Fatalf("diagnostic missing %s", field)
		}
	}
}
