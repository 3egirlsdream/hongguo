package core

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestStagedWarmRespectsBudgetAndReportsDiscardedTraffic(t *testing.T) {
	var calls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		w.Header().Set("Content-Type", "video/mp4")
		w.(http.Flusher).Flush()
		_, _ = w.Write([]byte(strings.Repeat("x", 4096)))
	}))
	defer server.Close()
	d := &Downloader{cfg: defaultConfig(), client: server.Client()}
	stream, err := newNativeStreamServer(d)
	if err != nil {
		t.Fatal(err)
	}
	defer stream.server.Close()
	entry, token := stream.nativeOpen(providerMedia{URL: server.URL + "/media.mp4"})
	if calls.Load() != 0 {
		t.Fatal("opening a session downloaded media")
	}
	cached, transferred := stream.nativePrefetchMeasured(context.Background(), token, entry, 0, 1024, 6)
	if cached != 0 || transferred != 1025 {
		t.Fatalf("ignored Range budget: cached=%d transferred=%d", cached, transferred)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	before := calls.Load()
	_, _ = stream.nativePrefetchMeasured(ctx, token, entry, 0, 1024, 6)
	if calls.Load() != before {
		t.Fatal("cancelled warm started another request")
	}
}

func TestCancellingWarmKeepsPlaybackSessionUsable(t *testing.T) {
	started := make(chan struct{})
	var calls atomic.Int32
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if calls.Add(1) == 1 {
			close(started)
			<-r.Context().Done()
			return
		}
		w.Header().Set("Content-Type", "video/mp4")
		_, _ = w.Write([]byte("synthetic-video"))
	}))
	defer upstream.Close()
	d := &Downloader{cfg: defaultConfig(), client: upstream.Client()}
	stream, err := newNativeStreamServer(d)
	if err != nil {
		t.Fatal(err)
	}
	defer stream.server.Close()
	entry, token := stream.nativeOpen(providerMedia{URL: upstream.URL + "/media.mp4"})
	engine := &nativeEngine{downloader: d, stream: stream, playbacks: map[string]nativePlaybackChoice{"next": {streamSession: token}}}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() {
		_, err := engine.nativeWarmPlayback(ctx, nativeInput{PlaybackSession: "next", MediaURL: entry, MaxBytes: 1024})
		done <- err
	}()
	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("warm request did not start")
	}
	cancel()
	select {
	case err := <-done:
		if err == nil {
			t.Fatal("cancelled warm succeeded")
		}
	case <-time.After(time.Second):
		t.Fatal("warm ignored cancellation")
	}
	response, err := http.Get(entry)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	body, _ := io.ReadAll(response.Body)
	if response.StatusCode != http.StatusOK || string(body) != "synthetic-video" {
		t.Fatalf("warm cancellation invalidated playback: %d %s", response.StatusCode, body)
	}
}
