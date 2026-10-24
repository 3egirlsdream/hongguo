package core

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/md5"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"
)

func historyFixtureWatch(sid, vid string) hgOfficialWatch {
	return hgOfficialWatch{Drama: nativeDrama{ID: "hongguo:" + sid, Source: sourceHongguo, SourceID: sid, Title: "合成历史", Episodes: 20}, VideoID: vid, Episode: 1, Position: 12, Duration: 60, UpdatedAt: time.Now().UTC().Truncate(time.Millisecond)}
}
func historyFixtureAccount(t *testing.T, transport sourceFixtureTransport) (*nativeEngine, *hgOfficialAccount) {
	t.Helper()
	engine := sourceFixtureEngine(t, transport)
	a, err := engine.officialAccount("default")
	if err != nil {
		t.Fatal(err)
	}
	a.disk.Profile = &hgAccountProfile{UID: "7000000000000000001"}
	a.disk.Session.Token = "fixture-secret"
	if err = a.loadLibrary(a.disk.Profile.UID); err != nil {
		t.Fatal(err)
	}
	return engine, a
}
func historyFixtureJSON(t *testing.T, r *http.Request, value any) *http.Response {
	t.Helper()
	raw, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	return sourceFixtureResponse(r, 200, string(raw))
}
func historyFixtureBody(t *testing.T, r *http.Request) map[string]any {
	t.Helper()
	raw, err := io.ReadAll(r.Body)
	if err != nil {
		t.Fatal(err)
	}
	if r.Header.Get("Content-Encoding") != "gzip" {
		t.Fatal("history write is not compressed")
	}
	if r.Header.Get("X-SS-STUB") != fmt.Sprintf("%X", md5.Sum(raw)) {
		t.Fatal("signature does not match transmitted compressed bytes")
	}
	z, err := gzip.NewReader(bytes.NewReader(raw))
	if err != nil {
		t.Fatal(err)
	}
	defer z.Close()
	decoded, err := io.ReadAll(z)
	if err != nil {
		t.Fatal(err)
	}
	result, err := hgDecodeObject(decoded)
	if err != nil {
		t.Fatal(err)
	}
	return result
}
func historyFixtureRow(w hgOfficialWatch) map[string]any {
	return map[string]any{"book_id_str": w.Drama.SourceID, "book_id": 1, "vid_str": w.VideoID, "vid_index": w.Episode - 1, "read_timestamp_ms": w.UpdatedAt.UnixMilli(), "current_play_position": int64(w.Position * 1000), "book_name": w.Drama.Title}
}
func TestHistoryRefreshIsReadOnlyAndAcceptsOverlappingPages(t *testing.T) {
	w := historyFixtureWatch("7000000000000000002", "7000000000000000003")
	calls := 0
	remote := w
	remote.Position = 25
	remote.UpdatedAt = w.UpdatedAt.Add(time.Second)
	engine, a := historyFixtureAccount(t, func(r *http.Request) (*http.Response, error) {
		if r.Method != http.MethodGet || r.URL.Path != "/reading/bookapi/read_history/list/v" {
			t.Fatalf("fetch attempted a write or unnecessary dependency: %s", r.URL.Path)
		}
		calls++
		if calls > 2 {
			t.Fatal("pagination did not finish")
		}
		offset := r.URL.Query().Get("offset")
		if calls == 1 && offset != "0" || calls == 2 && offset != "500" {
			t.Fatal("wrong cursor", offset)
		}
		return historyFixtureJSON(t, r, map[string]any{"code": 0, "data": map[string]any{"data_list": []any{historyFixtureRow(remote)}, "has_more": calls == 1, "next_offset": 500}}), nil
	})
	if err := a.queueProgress(hgAccountInput{UID: a.disk.Profile.UID, Watch: w}); err != nil {
		t.Fatal(err)
	}
	a.syncError = "previous upload failure"
	result, err := engine.nativeAccount(context.Background(), nativeInput{Profile: "default", Command: "history", Account: hgAccountInput{UID: a.disk.Profile.UID, Refresh: true}})
	if err != nil {
		t.Fatal(err)
	}
	if result.(map[string]any)["warning"] != "" || calls != 2 || len(a.library.Pending) != 1 {
		t.Fatal("fetch lost pending rows or rejected overlapping pages", result)
	}
	got := a.library.History[w.Drama.ID]
	if got.VideoID != w.VideoID || got.Episode != 1 || got.Position != 25 || len(a.library.History) != 1 || a.syncError != "previous upload failure" {
		t.Fatal("string identity or zero-based first episode was lost", got)
	}
}
func TestHistoryUploadWireAndRejectedSuccess(t *testing.T) {
	for _, reject := range []bool{false, true} {
		t.Run(fmt.Sprint(reject), func(t *testing.T) {
			w := historyFixtureWatch("7000000000000000002", "7000000000000000003")
			calls := 0
			client := hgNewAccountHTTP(sourceFixtureDownloader(t, func(r *http.Request) (*http.Response, error) {
				calls++
				body := historyFixtureBody(t, r)
				if calls == 1 {
					row := nestedMap(body["update_datas"].([]any)[0])
					if mapString(row, "book_id") != w.Drama.SourceID || mapString(row, "vid") != w.VideoID || mapString(row, "vid_index") != "0" || mapString(row, "is_multi_season") != "0" {
						t.Fatal("wire history incompatible", row)
					}
					if reject {
						return sourceFixtureResponse(r, 200, `{"code":0,"data":{"update_fail_datas":[{"book_id":"7000000000000000002"}]}}`), nil
					}
				} else {
					row := nestedMap(body["books"].([]any)[0])
					if row["book_id"] != w.Drama.SourceID || mapString(row, "vid_index") != "0" {
						t.Fatal("wire progress incompatible", row)
					}
				}
				return sourceFixtureResponse(r, 200, `{"code":0,"data":{"update_fail_datas":[]}}`), nil
			}), hgAccountSession{})
			err := client.uploadWatch(context.Background(), w)
			if reject && (err == nil || calls != 1) || !reject && (err != nil || calls != 2) {
				t.Fatal("wrong acknowledgement", err, calls)
			}
		})
	}
}
func TestHistorySyncCommitsPartialSuccessAndKeepsRejectedRows(t *testing.T) {
	first := historyFixtureWatch("7000000000000000002", "7000000000000000003")
	second := historyFixtureWatch("7000000000000000004", "7000000000000000005")
	confirmed := map[string]hgOfficialWatch{}
	_, a := historyFixtureAccount(t, func(r *http.Request) (*http.Response, error) {
		switch r.URL.Path {
		case "/reading/bookapi/read_history/list/v":
			rows := []any{}
			for _, w := range confirmed {
				rows = append(rows, historyFixtureRow(w))
			}
			return historyFixtureJSON(t, r, map[string]any{"code": 0, "data": map[string]any{"data_list": rows, "has_more": false}}), nil
		case "/reading/bookapi/read_history/update/v":
			row := nestedMap(historyFixtureBody(t, r)["update_datas"].([]any)[0])
			if mapString(row, "book_id") == first.Drama.SourceID {
				return sourceFixtureResponse(r, 200, `{"code":0,"data":{"update_fail_datas":[{}]}}`), nil
			}
			return sourceFixtureResponse(r, 200, `{"code":0}`), nil
		case "/reading/bookapi/read_progress/upload/v":
			confirmed[second.Drama.ID] = second
			return sourceFixtureResponse(r, 200, `{"code":0}`), nil
		default:
			t.Fatal("unexpected history operation", r.URL.Path)
			return nil, errors.New("unexpected request")
		}
	})
	for _, w := range []hgOfficialWatch{first, second} {
		if err := a.queueProgress(hgAccountInput{UID: a.disk.Profile.UID, Watch: w}); err != nil {
			t.Fatal(err)
		}
	}
	if err := a.syncHistory(context.Background(), a.disk.Profile.UID); err == nil {
		t.Fatal("partial rejection reported success")
	}
	if len(a.library.Pending) != 1 || a.library.Pending[first.Drama.ID].VideoID != first.VideoID {
		t.Fatal("acknowledged row repeated or rejected row lost", a.library.Pending)
	}
	if err := a.loadLibrary(a.disk.Profile.UID); err != nil || len(a.library.Pending) != 1 {
		t.Fatal("partial result not durable", err)
	}
}
func TestHistorySyncRequiresReadbackAndPreservesConcurrentProgress(t *testing.T) {
	for _, concurrent := range []bool{false, true} {
		t.Run(fmt.Sprint(concurrent), func(t *testing.T) {
			w := historyFixtureWatch("7000000000000000002", "7000000000000000003")
			reads := 0
			var a *hgOfficialAccount
			_, a = historyFixtureAccount(t, func(r *http.Request) (*http.Response, error) {
				switch r.URL.Path {
				case "/reading/bookapi/read_history/list/v":
					reads++
					rows := []any{}
					if reads > 1 && concurrent {
						newer := w
						newer.Position = 20
						newer.UpdatedAt = w.UpdatedAt.Add(time.Second)
						if err := a.queueProgress(hgAccountInput{UID: a.disk.Profile.UID, Watch: newer}); err != nil {
							t.Fatal(err)
						}
						rows = append(rows, historyFixtureRow(w))
					}
					return historyFixtureJSON(t, r, map[string]any{"code": 0, "data": map[string]any{"data_list": rows, "has_more": false}}), nil
				default:
					return sourceFixtureResponse(r, 200, `{"code":0}`), nil
				}
			})
			if err := a.queueProgress(hgAccountInput{UID: a.disk.Profile.UID, Watch: w}); err != nil {
				t.Fatal(err)
			}
			ctx := context.Background()
			if !concurrent {
				var cancel context.CancelFunc
				ctx, cancel = context.WithTimeout(ctx, 100*time.Millisecond)
				defer cancel()
			}
			err := a.syncHistory(ctx, a.disk.Profile.UID)
			if !concurrent && err == nil {
				t.Fatal("server code zero cleared an unconfirmed row")
			}
			if concurrent && err != nil {
				t.Fatal(err)
			}
			if len(a.library.Pending) != 1 {
				t.Fatal("pending progress disappeared")
			}
			if concurrent && a.library.Pending[w.Drama.ID].Position != 20 {
				t.Fatal("new progress replaced by old acknowledgement")
			}
		})
	}
}
func TestHistoryFetchFailureRetainsCacheAndPending(t *testing.T) {
	w := historyFixtureWatch("7000000000000000002", "7000000000000000003")
	engine, a := historyFixtureAccount(t, func(r *http.Request) (*http.Response, error) {
		return sourceFixtureResponse(r, 200, `{"code":0,"data":{"data_list":[],"has_more":true,"next_offset":0}}`), nil
	})
	if err := a.queueProgress(hgAccountInput{UID: a.disk.Profile.UID, Watch: w}); err != nil {
		t.Fatal(err)
	}
	result, err := engine.nativeAccount(context.Background(), nativeInput{Profile: "default", Command: "history", Account: hgAccountInput{UID: a.disk.Profile.UID, Refresh: true}})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(result.(map[string]any)["warning"].(string), "失败") || len(a.library.Pending) != 1 || len(a.library.History) != 1 {
		t.Fatal("bad response erased existing data", result)
	}
}

func TestHistoryAccountTokenUsesShortFormAndKeepsFullRenewal(t *testing.T) {
	full := strings.Repeat("a", 56) + "--" + strings.Repeat("b", 56) + "-3.0.3"
	next := strings.Repeat("c", 56) + "--" + strings.Repeat("d", 56) + "-3.0.3"
	calls := 0
	client := hgNewAccountHTTP(sourceFixtureDownloader(t, func(r *http.Request) (*http.Response, error) {
		expected := strings.Repeat("a", 56)
		if calls > 0 {
			expected = strings.Repeat("c", 56)
		}
		calls++
		if r.Header.Get("X-Tt-Token") != expected {
			t.Fatal("full refresh credential sent as access token")
		}
		if !strings.Contains(r.Header.Get("Cookie"), "sessionid=fixture-cookie") {
			t.Fatal("session cookie lost")
		}
		response := sourceFixtureResponse(r, 200, `{"code":100103,"message":"PARAM_INVALID"}`)
		response.Header.Set("X-Tt-Token", next)
		return response, nil
	}), hgAccountSession{Token: full, Cookies: map[string]string{"sessionid": "fixture-cookie"}})
	_, err := client.history(context.Background())
	if err == nil || !strings.Contains(err.Error(), "100103 / PARAM_INVALID") || !strings.Contains(err.Error(), "read_history/list/v") {
		t.Fatal("failure lost diagnostic path or server enum", err)
	}
	if client.session.Token != next || calls != 3 {
		t.Fatal("full renewed session was not retained")
	}
	if strings.Contains(err.Error(), "fixture-cookie") || strings.Contains(err.Error(), strings.Repeat("a", 56)) {
		t.Fatal("error exposes credentials")
	}
}

func TestHistoryNewerCloudProgressWinsWithoutUploading(t *testing.T) {
	local := historyFixtureWatch("7000000000000000002", "7000000000000000003")
	cloud := local
	cloud.VideoID = "7000000000000000004"
	cloud.Episode = 2
	cloud.Position = 30
	cloud.UpdatedAt = local.UpdatedAt.Add(time.Second)
	_, a := historyFixtureAccount(t, func(r *http.Request) (*http.Response, error) {
		if r.Method != http.MethodGet || r.URL.Path != "/reading/bookapi/read_history/list/v" {
			t.Fatal("newer cloud history overwritten")
		}
		return historyFixtureJSON(t, r, map[string]any{"code": 0, "data": map[string]any{"data_list": []any{historyFixtureRow(cloud)}, "has_more": false}}), nil
	})
	if err := a.queueProgress(hgAccountInput{UID: a.disk.Profile.UID, Watch: local}); err != nil {
		t.Fatal(err)
	}
	if err := a.syncHistory(context.Background(), a.disk.Profile.UID); err != nil {
		t.Fatal(err)
	}
	if len(a.library.Pending) != 0 || a.library.History[cloud.Drama.ID].VideoID != cloud.VideoID {
		t.Fatal("newer remote progress did not replace stale pending record")
	}
}

func TestHistoryConfirmationWaitsForEventualCloudVisibility(t *testing.T) {
	w := historyFixtureWatch("7000000000000000002", "7000000000000000003")
	reads := 0
	client := hgNewAccountHTTP(sourceFixtureDownloader(t, func(r *http.Request) (*http.Response, error) {
		reads++
		rows := []any{}
		if reads == 2 {
			old := w
			old.Position = 1
			rows = append(rows, historyFixtureRow(old))
		}
		if reads >= 3 {
			rows = append(rows, historyFixtureRow(w))
		}
		return historyFixtureJSON(t, r, map[string]any{"code": 0, "data": map[string]any{"data_list": rows, "has_more": false}}), nil
	}), hgAccountSession{})
	pauses := 0
	got, err := client.confirmHistory(context.Background(), map[string]hgOfficialWatch{w.Drama.ID: w}, func(context.Context, time.Duration) error { pauses++; return nil })
	if err != nil || reads != 3 || pauses != 3 || !hgWatchConfirmed(got[w.Drama.ID], w) {
		t.Fatal("delayed server write was not confirmed", err, reads)
	}
}

func TestHistoryReadRetriesTransient100103WithoutUploading(t *testing.T) {
	calls := 0
	client := hgNewAccountHTTP(sourceFixtureDownloader(t, func(r *http.Request) (*http.Response, error) {
		if r.Method != http.MethodGet {
			t.Fatal("read retry uploaded data")
		}
		calls++
		if calls < 3 {
			return sourceFixtureResponse(r, 200, `{"code":100103,"message":"PARAM_INVALID"}`), nil
		}
		return sourceFixtureResponse(r, 200, `{"code":0,"data":{"data_list":[],"has_more":false}}`), nil
	}), hgAccountSession{})
	rows, err := client.history(context.Background())
	if err != nil || calls != 3 || len(rows) != 0 {
		t.Fatal("transient request rejection did not recover", calls, err)
	}
}

func TestHistoryLegacyLastEpisodeDoesNotExceedSeriesLength(t *testing.T) {
	got, err := hgHistoryWatch(map[string]any{"book_id_str": "7000000000000000002", "vid_index": json.Number("141"), "episode_cnt": json.Number("141")})
	if err != nil || got.Episode != 141 {
		t.Fatal("legacy official last episode exceeded series length", got.Episode, err)
	}
}
