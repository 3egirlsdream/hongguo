package core

import (
	"context"
	"errors"
	"net/http"
	"testing"
	"time"
)

func TestReservationSingleRequestDuringHistorySync(t *testing.T) {
	for _, desired := range []bool{true, false} {
		calls := 0
		_, account := historyFixtureAccount(t, func(r *http.Request) (*http.Response, error) {
			calls++
			if r.URL.Path != "/reading/bookapi/search/uncover_subscribe/v" || r.Method != http.MethodPost {
				t.Fatalf("unexpected blocking dependency: %s", r.URL.Path)
			}
			body := historyFixtureBody(t, r)
			op := "2"
			if desired {
				op = "1"
			}
			if mapString(body, "item_id") != "7000000000000000002" || mapString(body, "op_type") != op {
				t.Fatal("incorrect reservation payload")
			}
			return historyFixtureJSON(t, r, map[string]any{"code": 0}), nil
		})
		account.operation.Lock()
		result, err := account.reservations(context.Background(), "reserve", hgAccountInput{UID: account.disk.Profile.UID, ID: "7000000000000000002", Reserved: desired})
		account.operation.Unlock()
		if err != nil {
			t.Fatal(err)
		}
		row := result.(map[string]any)
		if calls != 1 || row["confirmed"] != true || row["reserved"] != desired {
			t.Fatal("reservation did not complete in a single request", row, calls)
		}
	}
}

func TestReservationRejectsFailureAndAccountSwitch(t *testing.T) {
	for _, switched := range []bool{false, true} {
		var account *hgOfficialAccount
		_, account = historyFixtureAccount(t, func(r *http.Request) (*http.Response, error) {
			code := 1
			if switched {
				account.mu.Lock()
				account.generation++
				account.mu.Unlock()
				code = 0
			}
			return historyFixtureJSON(t, r, map[string]any{"code": code}), nil
		})
		if _, err := account.reserve(context.Background(), hgAccountInput{UID: account.disk.Profile.UID, ID: "7000000000000000002", Reserved: true}); err == nil {
			t.Fatal("must not confirm rejected or stale reservation")
		}
	}
}

func TestReservationListsBypassHistoryAndCancelOnlyOwnedRead(t *testing.T) {
	started := make(chan struct{})
	engine, account := historyFixtureAccount(t, func(r *http.Request) (*http.Response, error) {
		if r.URL.Path != "/reading/user/subscribe/list/v1/" {
			t.Errorf("unexpected endpoint %s", r.URL.Path)
		}
		if r.URL.Query().Get("is_online") == "false" {
			close(started)
			<-r.Context().Done()
			return nil, r.Context().Err()
		}
		return historyFixtureJSON(t, r, map[string]any{"code": 0, "data": map[string]any{"subscribe_items": []any{}, "has_more": false, "next_offset": 0}}), nil
	})
	nativeState.Lock()
	previous := nativeState.engine
	nativeState.engine = engine
	nativeState.Unlock()
	defer func() { nativeState.Lock(); nativeState.engine = previous; nativeState.Unlock() }()
	syncCtx, _, _, finish, err := account.begin(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	defer finish()
	input := nativeInput{Action: "hongguoAccount", Command: "reservations", Profile: "default", Session: "reservation-owner", Sequence: 1, Account: hgAccountInput{UID: account.disk.Profile.UID, Mode: "upcoming"}}
	done := make(chan error, 1)
	go func() { _, err := nativeDispatch(input); done <- err }()
	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("reservation read queued behind history")
	}
	if _, err := nativeDispatch(nativeInput{Action: "cancelRead", Session: input.Session, Sequence: 1}); err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-done:
		if err == nil {
			t.Fatal("cancelled read returned success")
		}
	case <-time.After(time.Second):
		t.Fatal("cancel did not reach HTTP request")
	}
	if syncCtx.Err() != nil || !account.busy {
		t.Fatal("read cancellation interrupted history synchronization")
	}
	input.Sequence = 2
	input.Account.Mode = "online"
	if _, err := nativeDispatch(input); err != nil {
		t.Fatalf("new read blocked: %v", err)
	}
}

func TestReservationReadRejectsChangedAccount(t *testing.T) {
	var account *hgOfficialAccount
	_, account = historyFixtureAccount(t, func(r *http.Request) (*http.Response, error) {
		account.mu.Lock()
		account.generation++
		account.mu.Unlock()
		response := historyFixtureJSON(t, r, map[string]any{"code": 0, "data": map[string]any{"subscribe_items": []any{}, "has_more": false}})
		response.Header.Set("X-Tt-Token", "stale-response")
		return response, nil
	})
	if _, err := account.reservations(context.Background(), "calendar", hgAccountInput{UID: account.disk.Profile.UID}); err == nil {
		t.Fatal("stale account result accepted")
	}
	if account.disk.Session.Token == "stale-response" {
		t.Fatal("stale credentials persisted")
	}
}

func TestConcurrentAccountReadsMergeCredentialsWithoutRollback(t *testing.T) {
	_, account := historyFixtureAccount(t, func(r *http.Request) (*http.Response, error) { return nil, errors.New("no network expected") })
	account.disk.Session.Cookies = map[string]string{"keep": "base", "rotate": "old", "remove": "old"}
	old := hgNewAccountHTTP(account.downloader, account.disk.Session)
	newer := hgNewAccountHTTP(account.downloader, account.disk.Session)
	newer.session.Token = "new-token"
	newer.session.Cookies["rotate"] = "new"
	newer.session.Cookies["remove"] = "new"
	newer.session.Cookies["other"] = "new"
	if err := account.persistClient(context.Background(), newer, account.generation); err != nil {
		t.Fatal(err)
	}
	old.session.Token = "old-token"
	old.session.Cookies["rotate"] = "old-response"
	old.session.Cookies["added"] = "old-response"
	delete(old.session.Cookies, "remove")
	if err := account.persistClient(context.Background(), old, account.generation); err != nil {
		t.Fatal(err)
	}
	session := account.disk.Session
	if session.Token != "new-token" || session.Cookies["rotate"] != "new" || session.Cookies["remove"] != "new" || session.Cookies["other"] != "new" || session.Cookies["added"] != "old-response" {
		t.Fatal("concurrent credential updates lost or rolled back")
	}
	if err := account.persistClient(context.Background(), newer, account.generation); err != nil {
		t.Fatal(err)
	}
	if account.disk.Session.Cookies["added"] != "old-response" {
		t.Fatal("unmodified cookies overwritten by later sync commit")
	}
}
