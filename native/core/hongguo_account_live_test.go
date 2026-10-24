package core

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"testing"
	"time"
)

type hgLiveHistoryTransport struct {
	base      http.RoundTripper
	t         *testing.T
	fullToken string
}

func (p hgLiveHistoryTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	allowed := map[string]string{"/reading/user/info/v1/": http.MethodGet, "/reading/bookapi/read_history/list/v": http.MethodGet, "/reading/bookapi/read_history/update/v": http.MethodPost, "/reading/bookapi/read_progress/upload/v": http.MethodPost, "/reading/bookapi/read_progress/get/v": http.MethodPost}
	if r.URL.Scheme != "https" || r.URL.Host != "api5-normal-lq.fqnovel.com" || allowed[r.URL.Path] != r.Method {
		return nil, errors.New("account probe blocked an unrelated request")
	}
	if p.fullToken != "" {
		r = r.Clone(r.Context())
		r.Header.Set("X-Tt-Token", p.fullToken)
	}
	response, err := p.base.RoundTrip(r)
	if err != nil {
		return nil, errors.New("live account endpoint connection failed")
	}
	raw, err := io.ReadAll(io.LimitReader(response.Body, 4<<20+1))
	response.Body.Close()
	if err != nil || len(raw) > 4<<20 {
		return nil, errors.New("live account endpoint response unreadable")
	}
	response.Body = io.NopCloser(bytes.NewReader(raw))
	object, _ := hgDecodeObject(raw)
	p.t.Logf("live method=%s endpoint=%s http=%d bytes=%d code=%s", r.Method, r.URL.Path, response.StatusCode, len(raw), mapString(object, "code"))
	if os.Getenv("HONGGUO_ACCOUNT_DIAGNOSE_FIELDS") == "1" {
		data := nestedMap(object, "data")
		keys := []string{}
		for key := range data {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		if r.Method == http.MethodPost {
			failed, _ := data["update_fail_datas"].([]any)
			p.t.Logf("live write response data_keys=%v rejected_rows=%d", keys, len(failed))
		}
		if r.Method == http.MethodGet && r.URL.Query().Get("offset") == "0" {
			rows, _ := data["data_list"].([]any)
			for _, value := range rows[:min(4, len(rows))] {
				row := nestedMap(value)
				p.t.Logf("live history sample title=%s wire_index=%s chapter_index=%s position_ms=%s duration_ms=%s", mapString(row, "book_name"), mapString(row, "vid_index"), mapString(row, "chapter_index"), mapString(row, "current_play_position"), mapString(row, "duration"))
			}
		}
	}

	return response, nil
}

type hgLiveAccountBundle struct {
	Session      hgAccountDisk     `json:"session"`
	PendingTotal int               `json:"pendingTotal"`
	Watches      []hgOfficialWatch `json:"watches"`
}

func TestHongguoAccountLiveHistory(t *testing.T) {
	path := os.Getenv("HONGGUO_ACCOUNT_BUNDLE_FILE")
	if path == "" {
		t.Skip("set HONGGUO_ACCOUNT_BUNDLE_FILE to an explicitly exported real account session")
	}
	if !filepath.IsAbs(path) {
		t.Fatal("real account bundle must use an absolute private file path")
	}
	info, err := os.Stat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0077 != 0 {
		t.Fatal("real account bundle must be a private regular file")
	}
	raw, err := os.ReadFile(path)
	if err != nil || len(raw) > 1<<20 {
		t.Fatal("real account bundle unavailable")
	}
	var bundle hgLiveAccountBundle
	if json.Unmarshal(raw, &bundle) != nil || bundle.Session.Profile == nil || !hgValidID(bundle.Session.Profile.UID) || !hgHasCredentials(bundle.Session.Session) || !bundle.Session.Session.Registered || !hgValidID(bundle.Session.Session.DeviceID) || !hgValidID(bundle.Session.Session.InstallID) {
		t.Fatal("real account bundle lacks a complete logged-in session and registered device")
	}
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal("account probe engine initialization failed")
	}
	t.Cleanup(engine.downloads.close)
	base := engine.downloader.client.Transport
	engine.downloader.client.Transport = hgLiveHistoryTransport{base: base, t: t}
	client := hgNewAccountHTTP(engine.downloader, bundle.Session.Session)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel()
	fingerprint := sha256.Sum256([]byte(bundle.Session.Profile.UID))
	t.Logf("real account fingerprint=%x pending_on_device=%d exported_candidates=%d", fingerprint[:6], bundle.PendingTotal, len(bundle.Watches))
	if os.Getenv("HONGGUO_ACCOUNT_PROFILE") == "1" {
		profile, profileErr := client.accountProfile(ctx, *bundle.Session.Profile)
		if profileErr != nil {
			t.Fatalf("real profile read failed: %v", profileErr)
		}
		if profile.Name == "" || profile.AvatarURL == "" || profile.PublicID == "" || profile.UID != bundle.Session.Profile.UID {
			t.Fatal("real profile is incomplete or changed session identity")
		}
		if expected := os.Getenv("HONGGUO_PROFILE_EXPECT_NAME"); expected != "" && profile.Name != expected {
			t.Fatal("real profile name does not match official App")
		}
		t.Logf("real profile name_matches_official=%v avatar_url_present=%v public_id_present=%v session_identity_preserved=%v", os.Getenv("HONGGUO_PROFILE_EXPECT_NAME") != "", profile.AvatarURL != "", profile.PublicID != "", profile.UID == bundle.Session.Profile.UID)
		return
	}
	before, readErr := client.history(ctx)
	if os.Getenv("HONGGUO_ACCOUNT_DIAGNOSE_LEGACY") == "1" {
		fullClient := hgNewAccountHTTP(engine.downloader, bundle.Session.Session)
		fullClient.http.Transport = hgLiveHistoryTransport{base: base, t: t, fullToken: bundle.Session.Session.Token}
		fullRows, fullErr := fullClient.history(ctx)
		t.Logf("diagnostic legacy_full_token history_count=%d error=%v", len(fullRows), fullErr)
		ids := []string{}
		for _, watch := range before {
			ids = append(ids, watch.Drama.SourceID)
		}
		sort.Strings(ids)
		for _, size := range []int{1, 50, 200} {
			if len(ids) < size {
				continue
			}
			batch := []json.Number{}
			for _, id := range ids[:size] {
				batch = append(batch, json.Number(id))
			}
			_, legacyErr := fullClient.json(ctx, "/reading/bookapi/read_progress/get/v", http.MethodPost, nil, map[string]any{"book_ids": map[string]any{"2": batch}}, false)
			t.Logf("diagnostic legacy_progress_get batch=%d error=%v", size, legacyErr)
		}

	}
	if readErr != nil {
		t.Fatalf("real account history read failed: %v", readErr)
	}
	if len(before) == 0 {
		t.Fatal("real account returned no history; authenticate against the official App before accepting this result")
	}
	t.Logf("real account history_read=confirmed records=%d", len(before))
	if os.Getenv("HONGGUO_ACCOUNT_UPLOAD") != "1" {
		t.Log("read-only probe; no history uploaded")
		return
	}
	sort.SliceStable(bundle.Watches, func(i, j int) bool { return bundle.Watches[i].UpdatedAt.After(bundle.Watches[j].UpdatedAt) })
	var selected *hgOfficialWatch
	for _, watch := range bundle.Watches {
		cloud, exists := before[watch.Drama.ID]
		if exists && cloud.UpdatedAt.After(watch.UpdatedAt) {
			continue
		}
		copy := watch
		if selected == nil || !exists {
			selected = &copy
		}
		if !exists {
			break
		}
	}
	if selected == nil {
		t.Fatal("no real pending watch is newer than cloud history; watch an episode in Yeguo and retry")
	}
	a, err := engine.officialAccount("live-account")
	if err != nil {
		t.Fatal(err)
	}
	a.disk = bundle.Session
	a.library = hgOfficialLibrary{UID: a.disk.Profile.UID, History: map[string]hgOfficialWatch{}, Pending: map[string]hgOfficialWatch{}}
	if err = a.queueProgress(hgAccountInput{UID: a.disk.Profile.UID, Watch: *selected}); err != nil {
		t.Fatal(err)
	}
	_, alreadyExisted := before[selected.Drama.ID]
	t.Logf("real upload target_series=%s episode=%d position_seconds=%.3f previously_in_cloud=%t", selected.Drama.SourceID, selected.Episode, selected.Position, alreadyExisted)
	if err = a.syncHistory(ctx, a.disk.Profile.UID); err != nil {
		t.Fatalf("real history upload or readback failed: %v", err)
	}
	if len(a.library.Pending) != 0 {
		t.Fatal("real uploaded record was not acknowledged")
	}
	after, err := hgNewAccountHTTP(engine.downloader, a.disk.Session).history(ctx)
	if err != nil {
		t.Fatalf("independent history readback failed: %v", err)
	}
	confirmed := after[selected.Drama.ID]
	if !hgWatchConfirmed(confirmed, *selected) {
		t.Fatal("independent cloud history does not contain the uploaded real watch")
	}
	t.Logf("real history upload=confirmed target_series=%s episode=%d position_seconds=%.3f records=%d", confirmed.Drama.SourceID, confirmed.Episode, confirmed.Position, len(after))
	fmt.Fprintln(os.Stdout, "Official Android App visibility must be verified separately on the connected device before release.")
}
