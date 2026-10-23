package core

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"
)

type hongguoProbeTransport struct {
	base http.RoundTripper
	t    *testing.T
}

func (p hongguoProbeTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	if r.Method != http.MethodHead && !strings.HasPrefix(r.URL.Path, "/player/") && !map[string]bool{
		"/service/2/device_register/":         true,
		"/novel/player/video_detail/v1/":      true,
		"/novel/player/multi_video_model/v1/": true,
		"/novel/player/video_model/v1/":       true,
		"/reading/bookapi/plan/v":             true,
		"/api/hongguo/play":                   true,
	}[r.URL.Path] {
		return nil, fmt.Errorf("probe blocked non-playback path %s", r.URL.Path)
	}
	start := time.Now()
	response, err := p.base.RoundTrip(r)
	if err != nil {
		p.t.Logf("%s %s%s network_error elapsed=%s", r.Method, r.URL.Host, r.URL.Path, time.Since(start).Round(time.Millisecond))
		return nil, err
	}
	if r.Method == http.MethodHead {
		p.t.Logf("HEAD media host=%s HTTP=%d type=%s length=%d", r.URL.Host, response.StatusCode, response.Header.Get("Content-Type"), response.ContentLength)
		return response, nil
	}
	content, err := io.ReadAll(io.LimitReader(response.Body, providerMaxBodyBytes+1))
	response.Body.Close()
	if err != nil {
		return nil, err
	}
	response.Body = io.NopCloser(bytes.NewReader(content))
	p.t.Logf("%s %s%s HTTP=%d bytes=%d elapsed=%s modern_signature=%t", r.Method, r.URL.Host, r.URL.Path, response.StatusCode, len(content), time.Since(start).Round(time.Millisecond), r.Header.Get("X-Medusa") != "")
	return response, nil
}

func TestHongguoAPILiveProbe(t *testing.T) {
	if os.Getenv("HONGGUO_API_PROBE") != "1" {
		t.Skip("set HONGGUO_API_PROBE=1 to make live API and media HEAD requests")
	}
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	d := engine.downloader
	d.client.Transport = hongguoProbeTransport{base: d.client.Transport, t: t}
	series := "7694653385668037657"
	for _, route := range []string{"guest_detail", "official_detail", "related_seasons"} {
		ctx, cancel := context.WithTimeout(context.Background(), 12*time.Second)
		started := time.Now()
		var probeErr error
		if route == "guest_detail" {
			_, probeErr = d.hongguoAppDetail(ctx, series)
		} else {
			account, err := engine.officialAccount("api-probe")
			if err != nil {
				t.Fatal(err)
			}
			if route == "official_detail" {
				client := hgNewAccountHTTP(d, account.disk.Session)
				probeErr = client.register(ctx)
				if probeErr == nil {
					account.disk.Session = hgCloneSession(client.session)
					var result map[string]any
					result, probeErr = client.json(ctx, "/novel/player/video_detail/v1/", http.MethodPost, nil, hongguoOfficialDetailPayload(series), false)
					if probeErr == nil {
						_, probeErr = parseHongguoAppDetail(result, series)
					}
				}
			} else {
				_, probeErr = account.seasons(ctx, series)
			}
		}
		cancel()
		if probeErr != nil {
			t.Logf("route=%s unavailable elapsed=%s: %s", route, time.Since(started).Round(time.Millisecond), publicError(probeErr))
			if route == "official_detail" {
				t.Error("official playback detail API did not return valid episodes")
			}
		} else {
			t.Logf("route=%s usable elapsed=%s", route, time.Since(started).Round(time.Millisecond))
		}
	}
	for _, video := range []string{"7694655440692448281", "7694655210777480217"} {
		for _, route := range []string{"app_batch", "app_single", "web_primary", "web_alias", "backup", "app_first_chain"} {
			ctx, cancel := context.WithTimeout(context.Background(), 12*time.Second)
			started := time.Now()
			var media providerMedia
			var resolveErr error
			var playbackSession string
			switch route {
			case "app_batch", "app_single":
				media, resolveErr = d.resolveHongguoAppMediaEndpoint(ctx, video, route == "app_batch")
			case "web_primary":
				media, resolveErr = d.resolveHongguoWebMediaAt(ctx, hongguoBaseURL, series, video)
			case "web_alias":
				media, resolveErr = d.resolveHongguoWebMediaAt(ctx, "https://novelquickapp.com", series, video)
			case "backup":
				backupCtx, stop := context.WithTimeout(ctx, 3*time.Second)
				media, resolveErr = d.resolveHongguoPlaybackAPI(backupCtx, series, video)
				stop()
			case "app_first_chain":
				trace := &playbackTrace{id: "probe-" + video, started: time.Now(), downloader: d}
				var plan nativePlan
				plan, resolveErr = engine.nativeResolve(context.WithValue(ctx, playbackTimingKey{}, trace), nativeInput{Drama: nativeDrama{ID: providerDramaID(sourceHongguo, series)}, Chapter: Chapter{VideoURL: "hongguo-cenc://" + video}, Force: true})
				playbackSession = plan.Session
				media = providerMedia{URL: plan.URL, Quality: plan.Quality}
				t.Logf("chain encrypted=%t quality=%d routes=%d", plan.Key != "", plan.Quality, plan.RouteCount)
				for _, stage := range trace.snapshot() {
					t.Logf("chain_stage=%s elapsed_ms=%d ok=%t", stage.Stage, stage.ElapsedMS, stage.OK)
					if strings.HasPrefix(stage.Stage, "web_") || stage.Stage == "backup" {
						t.Error("App-first chain fell back instead of using the healthy App API")
					}
				}
			}
			if resolveErr != nil {
				cancel()
				t.Logf("video=%s route=%s unavailable elapsed=%s: %s", video, route, time.Since(started).Round(time.Millisecond), publicError(resolveErr))
				if route == "app_batch" || route == "app_first_chain" {
					t.Errorf("App API did not resolve video %s", video)
				}
				continue
			}
			u, _ := url.Parse(media.URL)
			t.Logf("video=%s route=%s resolved elapsed=%s host=%s variants=%d encrypted=%t quality=%d", video, route, time.Since(started).Round(time.Millisecond), u.Host, len(media.Variants), len(media.CENCKey) > 0, media.Quality)
			r, err := http.NewRequestWithContext(ctx, http.MethodHead, media.URL, nil)
			if err != nil {
				t.Fatal(err)
			}
			r.Header.Set("User-Agent", hongguoAppUserAgent)
			r.Header.Set("Referer", media.Referer)
			response, err := d.doCatalogRequestWithTimeout(r, 8*time.Second)
			if err != nil {
				t.Logf("media HEAD unavailable: %s", publicError(err))
				if route == "app_batch" || route == "app_first_chain" {
					t.Errorf("App media HEAD failed for video %s", video)
				}
			} else {
				if (route == "app_batch" || route == "app_first_chain") && response.StatusCode != http.StatusOK && response.StatusCode != http.StatusPartialContent {
					t.Errorf("App media HEAD returned HTTP %d", response.StatusCode)
				}
				response.Body.Close()
			}
			if playbackSession != "" {
				engine.nativeReleasePlayback(playbackSession)
			}
			cancel()
		}
	}
}
