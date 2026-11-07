package core

import (
	"context"
	"net/http"
	"testing"
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
