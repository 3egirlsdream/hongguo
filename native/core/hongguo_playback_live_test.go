package core

import (
	"context"
	"net/http"
	"os"
	"testing"
	"time"
)

func TestHongguoRegisteredPlaybackLiveRegression(t *testing.T) {
	if os.Getenv("HONGGUO_PLAYBACK_REGRESSION") != "1" {
		t.Skip("set HONGGUO_PLAYBACK_REGRESSION=1 for playback API and media HEAD checks")
	}
	e, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	d := e.downloader
	d.client.Transport = hongguoProbeTransport{base: d.client.Transport, t: t}
	for _, id := range []string{"7702347589160553496", "7677100206306905150", "7700877568869665816", "7702347589160553496"} {
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		m, err := d.resolveHongguoAppMedia(ctx, id)
		if err != nil {
			cancel()
			t.Fatalf("episode=%s err=%v", id, publicError(err))
		}
		if m.Duration < 30*time.Second {
			t.Fatal("received a preview instead of a complete episode")
		}
		t.Logf("episode=%s resolved duration=%s quality=%d variants=%d encrypted=%t", id, m.Duration, m.Quality, len(m.Variants), len(m.CENCKey) > 0)
		r, _ := http.NewRequestWithContext(ctx, http.MethodHead, m.URL, nil)
		r.Header.Set("User-Agent", hongguoAppUserAgent)
		r.Header.Set("Referer", m.Referer)
		resp, err := d.client.Do(r)
		if err != nil {
			cancel()
			t.Fatal("media HEAD failed")
		}
		resp.Body.Close()
		t.Logf("media status=%d length=%d", resp.StatusCode, resp.ContentLength)
		if resp.StatusCode != 200 && resp.StatusCode != 206 {
			t.Error("media inaccessible")
		}
		cancel()
	}
}
