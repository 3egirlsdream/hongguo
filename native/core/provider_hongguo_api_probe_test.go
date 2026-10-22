package core

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"net/url"
	"os"
	"testing"
	"time"
)

type hongguoProbeTransport struct {
	base http.RoundTripper
	t    *testing.T
}

func (p hongguoProbeTransport) RoundTrip(r *http.Request) (*http.Response, error) {
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
	for _, video := range []string{"7694655440692448281", "7694655210777480217"} {
		ctx, cancel := context.WithTimeout(context.Background(), 55*time.Second)
		for _, route := range []string{"web", "app", "backup"} {
			var media providerMedia
			var resolveErr error
			switch route {
			case "web":
				media, resolveErr = d.resolveHongguoWebMedia(ctx, series, video)
			case "app":
				media, resolveErr = d.resolveHongguoAppMedia(ctx, video)
			case "backup":
				backupCtx, stop := context.WithTimeout(ctx, 12*time.Second)
				media, resolveErr = d.resolveHongguoPlaybackAPI(backupCtx, series, video)
				stop()
			}
			if resolveErr != nil {
				t.Logf("video=%s route=%s unavailable: %s", video, route, publicError(resolveErr))
				if route == "app" {
					t.Errorf("App API did not resolve video %s", video)
				}
				continue
			}
			u, _ := url.Parse(media.URL)
			t.Logf("video=%s route=%s resolved host=%s variants=%d encrypted=%t quality=%d", video, route, u.Host, len(media.Variants), len(media.CENCKey) > 0, media.Quality)
			r, err := http.NewRequestWithContext(ctx, http.MethodHead, media.URL, nil)
			if err != nil {
				t.Fatal(err)
			}
			r.Header.Set("User-Agent", hongguoAppUserAgent)
			r.Header.Set("Referer", media.Referer)
			response, err := d.doCatalogRequestWithTimeout(r, 8*time.Second)
			if err != nil {
				t.Logf("media HEAD unavailable: %s", publicError(err))
				if route == "app" {
					t.Errorf("App media HEAD failed for video %s", video)
				}
			} else {
				if route == "app" && response.StatusCode != http.StatusOK && response.StatusCode != http.StatusPartialContent {
					t.Errorf("App media HEAD returned HTTP %d", response.StatusCode)
				}
				response.Body.Close()
			}
		}
		cancel()
	}
}
