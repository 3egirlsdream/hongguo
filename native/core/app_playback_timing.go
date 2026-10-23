package core

import (
	"context"
	"io"
	"sync"
	"time"
)

type playbackTimingKey struct{}

type playbackTiming struct {
	Stage     string `json:"stage"`
	ElapsedMS int64  `json:"elapsedMs"`
	TotalMS   int64  `json:"totalMs"`
	OK        bool   `json:"ok"`
}

type playbackTrace struct {
	mu         sync.Mutex
	id         string
	started    time.Time
	downloader *Downloader
	entries    []playbackTiming
}

func (trace *playbackTrace) record(stage string, started time.Time, err error) {
	if trace == nil {
		return
	}
	entry := playbackTiming{Stage: stage, ElapsedMS: time.Since(started).Milliseconds(), TotalMS: time.Since(trace.started).Milliseconds(), OK: err == nil}
	trace.mu.Lock()
	trace.entries = append(trace.entries, entry)
	trace.mu.Unlock()
	level, message := "info", "完成"
	if err != nil {
		level, message = "warning", publicError(err).Error()
	}
	trace.downloader.recordDiagnostic(diagnosticEvent{Event: "playback_timing", Level: level, TraceID: trace.id, Stage: stage, ElapsedMS: entry.ElapsedMS, TotalMS: entry.TotalMS, Message: message})
}

func (trace *playbackTrace) snapshot() []playbackTiming {
	trace.mu.Lock()
	defer trace.mu.Unlock()
	return append([]playbackTiming(nil), trace.entries...)
}

func playbackTraceFrom(ctx context.Context) *playbackTrace {
	trace, _ := ctx.Value(playbackTimingKey{}).(*playbackTrace)
	return trace
}

func startPlaybackStage(ctx context.Context, stage string) func(error) {
	trace, started := playbackTraceFrom(ctx), time.Now()
	return func(err error) { trace.record(stage, started, err) }
}

type playbackFirstByteReader struct {
	io.Reader
	trace   *playbackTrace
	once    *sync.Once
	started time.Time
}

func (reader *playbackFirstByteReader) Read(buffer []byte) (int, error) {
	n, err := reader.Reader.Read(buffer)
	if n > 0 {
		reader.once.Do(func() { reader.trace.record("media_first_bytes", reader.started, nil) })
	}
	return n, err
}
