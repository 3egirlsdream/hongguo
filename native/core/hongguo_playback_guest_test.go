package core

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"testing"
	"time"
)

func TestHongguoPlayerReferenceSignatures(t *testing.T) {
	raw, err := os.ReadFile("testdata/hongguo-player-signatures.json")
	if err != nil {
		t.Fatal(err)
	}
	var vectors []struct {
		Query     string
		Body      *string
		Timestamp uint32
		Device    string
		Nonce     string
		Argus     string
		Ladon     string
	}
	if err := json.Unmarshal(raw, &vectors); err != nil {
		t.Fatal(err)
	}
	for _, vector := range vectors {
		var body []byte
		if vector.Body != nil {
			body = []byte(*vector.Body)
		}
		value, err := hex.DecodeString(vector.Nonce)
		if err != nil || len(value) != 11 {
			t.Fatal("invalid nonce fixture")
		}
		var nonce hongguoPlayerNonce
		copy(nonce[:], value)
		if got := hongguoPlayerArgus(vector.Query, body, vector.Timestamp, vector.Device, nonce); got != vector.Argus {
			t.Fatal("Argus differs from the independently generated reference vector")
		}
		if got := hongguoPlayerLadon("8662", vector.Timestamp, nonce[2:6]); got != vector.Ladon {
			t.Fatal("Ladon differs from the independently generated reference vector")
		}
	}
}

func TestHongguoPlaybackUsesRegisteredSessionFirst(t *testing.T) {
	registrations, requests := 0, 0
	d := &Downloader{cfg: defaultConfig(), limiter: newRequestLimiter(1, 0)}
	d.client = &http.Client{Transport: hongguoPlaybackTestTransport(func(r *http.Request) (*http.Response, error) {
		if r.Header.Get("X-Tt-Token") != "" || r.Header.Get("Cookie") != "" {
			t.Fatal("playback guest leaked account credentials")
		}
		switch r.URL.Path {
		case "/service/2/device_register/":
			registrations++
			if r.Header.Get("Content-Encoding") != "" {
				t.Fatal("playback registration must use JSON")
			}
			var body map[string]any
			if json.NewDecoder(r.Body).Decode(&body) != nil {
				t.Fatal("invalid registration JSON")
			}
			header := nestedMap(body, "header")
			if mapString(header, "app_version") != "7.3.5.32" || mapString(header, "cdid") == "" || mapString(header, "clientudid") == "" {
				t.Fatal("registration lacks matching app and device identity")
			}
			return hongguoPlaybackTestResponse(r, `{"device_id_str":"1234567890123456","install_id_str":"1234567890123457"}`), nil
		case "/novel/player/video_model/v1/":
			requests++
			if r.URL.Query().Get("device_id") != "1234567890123456" || r.URL.Query().Get("iid") != "1234567890123457" {
				t.Fatal("registered identity not reused")
			}
			assertHongguoPlaybackSignatures(t, r)
			return hongguoPlaybackTestResponse(r, `{"code":0,"data":{"video_model":{"video_duration":60,"video_list":[{"main_url":"https://example.test/current.mp4"}]}}}`), nil
		default:
			t.Fatalf("healthy playback used legacy endpoint %s", r.URL.Path)
			return nil, nil
		}
	})}
	ctx := context.WithValue(context.Background(), hongguoPlaybackSessionKey{}, hgAccountSession{Token: "synthetic-token", Cookies: map[string]string{"sessionid": "synthetic-cookie"}})
	for _, id := range []string{"22", "23", "22"} {
		media, err := d.resolveHongguoAppMedia(ctx, id)
		if err != nil || media.Duration != time.Minute {
			t.Fatalf("playback failed: %v", err)
		}
	}
	if registrations != 1 || requests != 3 {
		t.Fatalf("registrations=%d requests=%d", registrations, requests)
	}
}

func TestHongguoPlaybackGuestEmptyRecoveryIsBounded(t *testing.T) {
	for _, retryAfter := range []string{"", "60"} {
		t.Run(retryAfter, func(t *testing.T) {
			registrations, requests := 0, 0
			d := &Downloader{cfg: defaultConfig(), limiter: newRequestLimiter(1, 0)}
			d.client = &http.Client{Transport: hongguoPlaybackTestTransport(func(r *http.Request) (*http.Response, error) {
				if r.URL.Path == "/service/2/device_register/" {
					registrations++
					return hongguoPlaybackTestResponse(r, `{"device_id_str":"1234567890123456","install_id_str":"1234567890123457"}`), nil
				}
				requests++
				response := hongguoPlaybackTestResponse(r, "")
				if retryAfter != "" {
					response.Header.Set("Retry-After", retryAfter)
				}
				return response, nil
			})}
			_, err := d.resolveHongguoRegisteredGuestMedia(context.Background(), "22")
			if err == nil {
				t.Fatal("empty playback was accepted")
			}
			want := 2
			if retryAfter != "" {
				want = 1
			}
			if registrations != want || requests != want {
				t.Fatalf("registrations=%d requests=%d", registrations, requests)
			}
		})
	}
}

func TestHongguoPlaybackCancellationWhileWaitingForGuest(t *testing.T) {
	d := &Downloader{cfg: defaultConfig(), limiter: newRequestLimiter(1, 0)}
	client := d.hongguoClient()
	client.playbackGuestGate <- struct{}{}
	defer func() { <-client.playbackGuestGate }()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { _, err := d.resolveHongguoRegisteredGuestMedia(ctx, "22"); done <- err }()
	cancel()
	select {
	case err := <-done:
		if !errors.Is(err, context.Canceled) {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("canceled foreground playback remained blocked behind preloading")
	}
}
