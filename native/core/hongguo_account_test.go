package core

import (
	"bytes"
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestHongguoAccountProtocolVectors(t *testing.T) {
	var v struct {
		Query, Body, SM3, F13, Proto, Helios, Gorgon string
		TS, IV                                       uint32
		AES                                          []string `json:"aes_v3"`
	}
	raw, e := os.ReadFile("testdata/hongguo-account-vectors.json")
	if e != nil {
		t.Fatal(e)
	}
	if e = json.Unmarshal(raw, &v); e != nil {
		t.Fatal(e)
	}
	iv, h, m := hgAuthDigest(v.Query, []byte(v.Body), v.TS)
	if iv != v.IV || hex.EncodeToString(h[:]) != v.SM3 {
		t.Fatal("account digest differs from independent wire vector")
	}
	f := hgAuthF13(iv, v.TS, h, m)
	if hex.EncodeToString(f) != v.F13 {
		t.Fatal("F13 mismatch")
	}
	if got := hgAuthEnvelope(v.Query, v.TS, 0x12345678, "7000000000000000001", h, m, f); hex.EncodeToString(got) != v.Proto {
		t.Fatal("Passport protobuf mismatch")
	}
	if hgAuthHelios(v.TS, 0x12345678) != v.Helios {
		t.Fatal("Helios mismatch")
	}
	if hgAuthGorgon(v.Query, []byte(v.Body), v.TS, 0x4567) != v.Gorgon {
		t.Fatal("Gorgon mismatch")
	}
	input := make([]byte, 256)
	for i := range input {
		input[i] = byte(i)
	}
	for i, want := range v.AES {
		got, e := hgAuthAES(input, v.TS+uint32(i))
		if e != nil || hex.EncodeToString(got) != want {
			t.Fatalf("AES branch %d mismatch: %v", i, e)
		}
	}
}
func TestHongguoAccountCookiesAreIsolatedAndNeverInStatus(t *testing.T) {
	engine := sourceFixtureEngine(t, func(*http.Request) (*http.Response, error) { return nil, errors.New("network forbidden") })
	a, e := engine.officialAccount("default")
	if e != nil {
		t.Fatal(e)
	}
	b, e := engine.officialAccount("viewer")
	if e != nil {
		t.Fatal(e)
	}
	a.mu.Lock()
	a.disk.Profile = &hgAccountProfile{UID: "7000000000000000001", Name: "synthetic"}
	a.disk.Session.Token = "fixture-secret"
	a.disk.Session.Cookies = map[string]string{"sessionid": "fixture-cookie"}
	a.library = hgOfficialLibrary{UID: a.disk.Profile.UID, History: map[string]hgOfficialWatch{}, Pending: map[string]hgOfficialWatch{}}
	a.mu.Unlock()
	client := hgNewAccountHTTP(engine.downloader, a.disk.Session)
	client.session.Cookies["sessionid"] = "changed"
	if a.disk.Session.Cookies["sessionid"] != "fixture-cookie" {
		t.Fatal("session clone shared cookies")
	}
	encoded, _ := json.Marshal(a.status())
	if bytes.Contains(encoded, []byte("fixture-secret")) || bytes.Contains(encoded, []byte("fixture-cookie")) {
		t.Fatal("status exposed credentials")
	}
	if b.status()["loggedIn"] != false {
		t.Fatal("local profiles shared account")
	}
	if _, e = engine.officialAccount("../escape"); e == nil {
		t.Fatal("unsafe profile accepted")
	}
}
func TestHongguoPendingProgressPersistsAcrossLogoutAndCancel(t *testing.T) {
	engine := sourceFixtureEngine(t, func(*http.Request) (*http.Response, error) { return nil, errors.New("network forbidden") })
	a, e := engine.officialAccount("default")
	if e != nil {
		t.Fatal(e)
	}
	uid := "7000000000000000001"
	a.disk.Profile = &hgAccountProfile{UID: uid}
	a.disk.Session.Token = "fixture-secret"
	if e = a.loadLibrary(uid); e != nil {
		t.Fatal(e)
	}
	w := hgOfficialWatch{Drama: nativeDrama{ID: "hongguo:7000000000000000002", Source: sourceHongguo, SourceID: "7000000000000000002", Title: "synthetic"}, Episode: 1, VideoID: "7000000000000000003", Position: 12, Duration: 60, UpdatedAt: time.Now().UTC()}
	if e = a.queueProgress(hgAccountInput{UID: uid, Watch: w}); e != nil {
		t.Fatal(e)
	}
	ctx, c, g, finish, e := a.begin(context.Background())
	if e != nil {
		t.Fatal(e)
	}
	if e = a.cancelLogin(true); e != nil {
		t.Fatal(e)
	}
	if ctx.Err() == nil {
		t.Fatal("logout did not cancel outstanding request")
	}
	if e = a.persistClient(ctx, c, g); e == nil {
		t.Fatal("late request restored logged-out credentials")
	}
	finish()
	if e = a.loadLibrary(uid); e != nil || len(a.library.Pending) != 1 {
		t.Fatal("logout discarded pending progress", e)
	}
	if e = a.queueProgress(hgAccountInput{UID: uid, Watch: w}); e == nil {
		t.Fatal("logged-out write accepted")
	}
	b, e := os.ReadFile(filepath.Join(a.dir, "session.json"))
	if e != nil || strings.Contains(string(b), "fixture-secret") {
		t.Fatal("logout left persisted token", e)
	}
}
func TestHongguoDeviceCipherRoundTripAndTampering(t *testing.T) {
	seed := make([]byte, 32)
	plain := []byte(`{"fixture":"device-registration"}`)
	cipher, e := hgDeviceCipher(plain, seed)
	if e != nil {
		t.Fatal(e)
	}
	got, e := hgDevicePlain(cipher)
	if e != nil || !bytes.Equal(got, plain) {
		t.Fatal("device encryption round trip failed", e)
	}
	cipher[len(cipher)-1] ^= 1
	if _, e = hgDevicePlain(cipher); e == nil {
		t.Fatal("tampered device response accepted")
	}
}
