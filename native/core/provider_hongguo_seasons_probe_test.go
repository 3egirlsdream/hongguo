package core

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"
)

type hongguoSeasonsProbeTransport struct {
	base http.RoundTripper
	t    *testing.T
}

func (transport hongguoSeasonsProbeTransport) RoundTrip(request *http.Request) (*http.Response, error) {
	allowed := map[string]bool{
		"/service/2/device_register/":                 true,
		"/novel/player/video_detail/v1/":              true,
		"/reading/bookapi/plan/v":                     true,
		"/reading/user/subscribe/list/v1/":            true,
		"/reading/bookapi/search/uncover_subscribe/v": true,
	}
	if !allowed[request.URL.Path] {
		return nil, fmt.Errorf("probe blocked path %s", request.URL.Path)
	}
	response, err := transport.base.RoundTrip(request)
	if err == nil {
		transport.t.Logf("%s %s HTTP=%d bytes=%d", request.Method, request.URL.Path, response.StatusCode, response.ContentLength)
	}
	return response, err
}

func TestHongguoSeasonsAPILiveProbe(t *testing.T) {
	if os.Getenv("HONGGUO_SEASONS_API_PROBE") != "1" {
		t.Skip("set HONGGUO_SEASONS_API_PROBE=1")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 55*time.Second)
	defer cancel()
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.Proxy = nil
	engine.downloader.client.Transport = hongguoSeasonsProbeTransport{base: transport, t: t}
	account, err := engine.officialAccount("default")
	if err != nil {
		t.Fatal(err)
	}
	if path := os.Getenv("HONGGUO_PROBE_SESSION"); path != "" {
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatal("local session unavailable")
		}
		var disk hgAccountDisk
		if json.Unmarshal(raw, &disk) != nil || disk.Profile == nil || !hgHasCredentials(disk.Session) {
			t.Fatal("valid login required")
		}
		account.disk = disk
	}
	var evidence []any
	for _, sample := range []struct {
		id            string
		current, next int
		reservable    bool
	}{
		{"7687961503718198334", 3, 4, false},
		{"7697841626730728510", 4, 5, true},
	} {
		detail, err := engine.nativeDetail(ctx, nativeDrama{ID: providerDramaID(sourceHongguo, sample.id), Source: sourceHongguo}, "default")
		if err != nil {
			t.Fatal(err)
		}
		chapters := detail.(map[string]any)["chapters"].([]Chapter)
		if len(chapters) == 0 {
			t.Fatal("no official episodes")
		}
		response, err := account.seasons(ctx, sample.id)
		if err != nil {
			t.Fatal(err)
		}
		if response.CurrentSeason != sample.current {
			t.Fatalf("current season=%d expected=%d", response.CurrentSeason, sample.current)
		}
		var next *hongguoOfficialSeason
		for i := range response.Seasons {
			if response.Seasons[i].Next {
				next = &response.Seasons[i]
				break
			}
		}
		if next == nil || next.Number != sample.next || next.Reservable != sample.reservable || next.Playable == sample.reservable {
			t.Fatalf("wrong next season: %+v", next)
		}
		rows := []any{}
		for _, season := range response.Seasons {
			rows = append(rows, map[string]any{"id": season.Drama.SourceID, "number": season.Number, "playable": season.Playable, "reservable": season.Reservable, "next": season.Next})
		}
		evidence = append(evidence, map[string]any{"seriesId": sample.id, "currentSeason": response.CurrentSeason, "officialEpisodes": len(chapters), "seasons": rows})
		t.Logf("series=%s current=%d official_episodes=%d next=%d playable=%t reservable=%t", sample.id, response.CurrentSeason, len(chapters), next.Number, next.Playable, next.Reservable)
	}
	client := hgNewAccountHTTP(engine.downloader, account.disk.Session)
	if _, err = client.reservationPage(ctx, "upcoming", 0, "", false, nil); err != nil {
		t.Fatal(err)
	}
	if directory := os.Getenv("HONGGUO_PROBE_EVIDENCE"); directory != "" {
		if err = os.MkdirAll(directory, 0700); err != nil {
			t.Fatal(err)
		}
		data, _ := json.MarshalIndent(map[string]any{"samples": evidence, "reservationListVerified": true, "authenticated": account.disk.Profile != nil}, "", "  ")
		if err = os.WriteFile(filepath.Join(directory, "production-seasons-api-evidence.json"), data, 0600); err != nil {
			t.Fatal(err)
		}
	}
}

func TestHongguoReservationAPIRoundTripLiveProbe(t *testing.T) {
	if os.Getenv("HONGGUO_RESERVATION_API_PROBE") != "1" {
		t.Skip("set HONGGUO_RESERVATION_API_PROBE=1 to change and restore one reservation")
	}
	raw, err := os.ReadFile(os.Getenv("HONGGUO_PROBE_SESSION"))
	if err != nil {
		t.Fatal("local login session unavailable")
	}
	var disk hgAccountDisk
	if json.Unmarshal(raw, &disk) != nil || disk.Profile == nil || !hgHasCredentials(disk.Session) {
		t.Fatal("valid local login required")
	}
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.Proxy = nil
	engine.downloader.client.Transport = hongguoSeasonsProbeTransport{base: transport, t: t}
	account, err := engine.officialAccount("default")
	if err != nil {
		t.Fatal(err)
	}
	account.disk = disk
	sid := "7699433423269547033"
	if v := os.Getenv("HONGGUO_PROBE_RESERVATION"); v != "" {
		sid = v
	}
	uid := disk.Profile.UID
	read := func(ctx context.Context) (bool, error) {
		found := false
		for _, mode := range []string{"online", "upcoming"} {
			offset := 0
			cursor := ""
			for page := 0; page < 100; page++ {
				value, err := account.reservations(ctx, "reservations", hgAccountInput{UID: uid, Mode: mode, Offset: offset, Cursor: cursor})
				if err != nil {
					return false, err
				}
				result := value.(map[string]any)
				for _, row := range result["items"].([]hgReservation) {
					if row.ID == sid {
						found = true
					}
				}
				if result["hasMore"] != true {
					break
				}
				offset = result["offset"].(int)
				cursor = mapString(result, "cursor")
				if page == 99 {
					return false, fmt.Errorf("incomplete reservation list")
				}
			}
		}
		return found, nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	original, err := read(ctx)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("target=%s original_reserved=%t", sid, original)
	restored := false
	t.Cleanup(func() {
		if restored {
			return
		}
		restoreCtx, stop := context.WithTimeout(context.Background(), 90*time.Second)
		defer stop()
		_, err := account.reservations(restoreCtx, "reserve", hgAccountInput{UID: uid, ID: sid, Reserved: original})
		if err != nil {
			t.Errorf("RESTORE_FAILED target=%s desired=%t: %v", sid, original, err)
			return
		}
		actual, err := read(restoreCtx)
		if err != nil || actual != original {
			t.Errorf("RESTORE_UNCONFIRMED target=%s", sid)
			return
		}
		t.Logf("original reservation restored=%t", original)
	})
	for _, desired := range []bool{!original, original} {
		value, err := account.reservations(ctx, "reserve", hgAccountInput{UID: uid, ID: sid, Reserved: desired})
		if err != nil {
			t.Fatal(err)
		}
		result := value.(map[string]any)
		if result["confirmed"] != true || result["reserved"] != desired {
			t.Fatalf("operation not confirmed: desired=%t", desired)
		}
		actual, err := read(ctx)
		if err != nil || actual != desired {
			t.Fatalf("independent list read did not match desired=%t: %v", desired, err)
		}
		t.Logf("target=%s reserved=%t independently_confirmed=true", sid, desired)
	}
	restored = true
	if directory := os.Getenv("HONGGUO_PROBE_EVIDENCE"); directory != "" {
		data, _ := json.MarshalIndent(map[string]any{"target": sid, "originalReserved": original, "reserveAndCancelConfirmed": true, "originalStateRestored": true}, "", "  ")
		if err = os.WriteFile(filepath.Join(directory, "reservation-roundtrip-evidence.json"), data, 0600); err != nil {
			t.Fatal(err)
		}
	}
}
