package core

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/sha512"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"
)

type hongguoPlaybackTestTransport func(*http.Request) (*http.Response, error)

func (f hongguoPlaybackTestTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	return f(r)
}

func hongguoPlaybackTestResponse(r *http.Request, body string) *http.Response {
	return &http.Response{StatusCode: http.StatusOK, Header: http.Header{}, Body: io.NopCloser(strings.NewReader(body)), Request: r}
}

func TestHongguoPublicWebPlayback(t *testing.T) {
	for _, tc := range []struct {
		name, video, series, canonical string
		available                      bool
		want                           bool
	}{
		{"episode canonical", "22", "11", "https://hongguoduanju.com/player/11/22", true, true},
		{"series canonical", "22", "11", "https://hongguoduanju.com/player/11", true, true},
		{"another episode", "23", "11", "https://hongguoduanju.com/player/11/23", true, false},
		{"another series", "22", "12", "https://hongguoduanju.com/player/12", true, false},
		{"recommended schema", "22", "11", "https://hongguoduanju.com/player/11/23", true, false},
		{"unavailable", "22", "11", "https://hongguoduanju.com/player/11", false, false},
		{"foreign canonical", "22", "11", "https://example.test/player/11", true, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			page := map[string]any{
				"isSuccess":      true,
				"seriesDetail":   map[string]any{"series_id": "11"},
				"publicVideoSeo": map[string]any{"available": tc.available, "itemId": tc.video, "seriesId": tc.series},
			}
			schema, _ := json.Marshal(map[string]any{"@type": "VideoObject", "url": tc.canonical, "@id": tc.canonical + "#video", "contentUrl": "https://example.test/current.mp4"})
			body := `<script type="application/ld+json">` + string(schema) + `</script>`
			media, ok := hongguoPublicWebMedia(body, "https://novelquickapp.com", "11", "22", page)
			if ok != tc.want || ok && media.URL != "https://example.test/current.mp4" {
				t.Fatalf("ok=%t media=%v", ok, media)
			}
		})
	}
}

func TestHongguoBatchPlaybackSession(t *testing.T) {
	for _, authenticated := range []bool{false, true} {
		t.Run(fmt.Sprint(authenticated), func(t *testing.T) {
			d := &Downloader{cfg: defaultConfig(), limiter: newRequestLimiter(1, 0)}
			calls := 0
			d.client = &http.Client{Transport: hongguoPlaybackTestTransport(func(r *http.Request) (*http.Response, error) {
				calls++
				if r.URL.Path != "/novel/player/multi_video_model/v1/" || r.Method != http.MethodPost {
					t.Fatalf("unexpected endpoint %s %s", r.Method, r.URL.Path)
				}
				if r.Header.Get("X-Medusa") == "" || r.Header.Get("X-Helios") == "" || r.Header.Get("X-Gorgon") == "" {
					t.Fatal("missing playback signatures")
				}
				if authenticated {
					if r.URL.Query().Get("device_id") != "7000000000000000001" || r.URL.Query().Get("iid") != "7000000000000000002" || r.Header.Get("X-Tt-Token") != "synthetic-token" || !strings.Contains(r.Header.Get("Cookie"), "sessionid=synthetic-session") {
						t.Fatal("current account identity was not attached")
					}
				} else if r.Header.Get("X-Tt-Token") != "" || r.Header.Get("Cookie") != "" {
					t.Fatal("guest request contains account credentials")
				}
				var body map[string]any
				if json.NewDecoder(r.Body).Decode(&body) != nil || mapString(nestedMap(body, "biz_param"), "video_platform") != "1024" || len(anyList(nestedMap(body, "mixed_video_id_map")["1004"])) != 1 {
					t.Fatal("incorrect batch body")
				}
				return hongguoPlaybackTestResponse(r, `{"code":0,"data":{"22":{"video_model":{"video_list":[{"main_url":"https://example.test/current.mp4","video_meta":{"codec_type":"h264","definition":"1080p"}}]}},"23":{"video_model":{"video_list":[{"main_url":"https://example.test/wrong.mp4"}]}}}}`), nil
			})}
			ctx := context.Background()
			if authenticated {
				ctx = context.WithValue(ctx, hongguoPlaybackSessionKey{}, hgAccountSession{DeviceID: "7000000000000000001", InstallID: "7000000000000000002", Token: "synthetic-token", Cookies: map[string]string{"sessionid": "synthetic-session"}})
			}
			media, err := d.resolveHongguoAppMedia(ctx, "22")
			if err != nil || media.URL != "https://example.test/current.mp4" || media.Quality != 1080 || calls != 1 {
				t.Fatalf("media=%v calls=%d err=%v", media, calls, err)
			}
		})
	}
}

func TestHongguoFallbackPlayback(t *testing.T) {
	d := &Downloader{cfg: defaultConfig(), limiter: newRequestLimiter(1, 0)}
	calls := 0
	d.client = &http.Client{Transport: hongguoPlaybackTestTransport(func(r *http.Request) (*http.Response, error) {
		calls++
		if r.Method == http.MethodPost {
			return hongguoPlaybackTestResponse(r, `{"code":0,"data":{"22":{"video_model":"{\"fallback_api\":\"https://vod.snssdk.com/info?token=synthetic\"}"}}}`), nil
		}
		if r.URL.Host != "vod.snssdk.com" || r.Header.Get("X-Tt-Token") != "" || r.Header.Get("Cookie") != "" || r.Header.Get("X-Medusa") != "" {
			t.Fatal("fallback request leaked account credentials or used wrong host")
		}
		return hongguoPlaybackTestResponse(r, `{"video_info":{"data":{"video_list":{"h264":{"backup_url_list":["https://example.test/fallback.mp4"],"codec_type":"h264","width":1080,"height":1920}}}}}`), nil
	})}
	ctx := context.WithValue(context.Background(), hongguoPlaybackSessionKey{}, hgAccountSession{DeviceID: "7000000000000000001", InstallID: "7000000000000000002", Token: "synthetic-token"})
	media, err := d.resolveHongguoAppMedia(ctx, "22")
	if err != nil || media.URL != "https://example.test/fallback.mp4" || media.Quality != 1080 || calls != 2 {
		t.Fatalf("media=%v calls=%d err=%v", media, calls, err)
	}
	for _, address := range []string{"http://vod.snssdk.com/info", "https://snssdk.com.example.test/info", "https://user@vod.snssdk.com/info", "https://vod.snssdk.com:8443/info"} {
		if _, err := d.hongguoFallbackModel(ctx, address); err == nil {
			t.Fatal("invalid fallback accepted")
		}
	}
}

func TestHongguoEncryptedMediaAddress(t *testing.T) {
	seed := []byte("synthetic-key-seed")
	address := "https://example.test/current.mp4?token=synthetic"
	constants, _ := hex.DecodeString("4dd4c2e6b83162090e52b3c7a6733ba41cb2462b829ab58a196b39db57177524f49baf7f08e8d68d26a72e37c1a95a2f1f05a51892aef2949732b62a38aadd58")
	hash := sha512.Sum512(seed)
	material := sha512.Sum512(append(hash[:], constants...))
	block, _ := aes.NewCipher(material[:16])
	plain := hongguoCommentPad([]byte(address))
	encrypted := make([]byte, len(plain))
	cipher.NewCBCEncrypter(block, material[16:32]).CryptBlocks(encrypted, plain)
	value := base64.StdEncoding.EncodeToString(append([]byte{0xa8, 0, 1, 0}, encrypted...))
	got, err := hongguoDecodeMediaAddress(value, seed)
	if err != nil || got != address {
		t.Fatalf("address=%s err=%v", got, err)
	}
	if _, err := hongguoDecodeMediaAddress(value, []byte("wrong-seed")); err == nil {
		t.Fatal("incorrect seed accepted")
	}
}

func TestHongguoPlaybackCancellation(t *testing.T) {
	d := &Downloader{cfg: defaultConfig(), limiter: newRequestLimiter(1, 0), client: &http.Client{Transport: hongguoPlaybackTestTransport(func(r *http.Request) (*http.Response, error) {
		t.Fatal("canceled playback issued a network request")
		return nil, context.Canceled
	})}}
	ctx, cancel := context.WithDeadline(context.Background(), time.Now().Add(-time.Second))
	defer cancel()
	if _, err := d.resolveHongguoAppMedia(ctx, "22"); err == nil {
		t.Fatal("canceled playback did not fail")
	}
}
