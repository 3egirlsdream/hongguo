package core

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"testing"
)

func TestHongguoProfileUsesReadingIdentityAndPreservesSessionOwner(t *testing.T) {
	_, a := historyFixtureAccount(t, func(r *http.Request) (*http.Response, error) {
		if r.URL.Path != "/reading/user/info/v1/" || r.Method != http.MethodGet {
			t.Fatalf("unexpected profile request: %s %s", r.Method, r.URL.Path)
		}
		return historyFixtureJSON(t, r, map[string]any{"code": 0, "data": map[string]any{"user_name": "合成真实昵称", "avatar_url": "https://avatar.example.test/account.png", "req_id": "7000000000000000001", "user_id": "#encoded_user", "biz_user_id": "7000000000000000002"}}), nil
	})
	a.disk.Profile.Name = "用户123456"
	a.disk.Profile.Phone = "138****0000"
	if err := a.refreshProfile(context.Background(), a.disk.Profile.UID); err != nil {
		t.Fatal(err)
	}
	p := a.disk.Profile
	if p.UID != "7000000000000000001" || p.Name != "合成真实昵称" || p.Phone != "138****0000" || p.AvatarURL != "https://avatar.example.test/account.png" || p.PublicID != "7000000000000000002" {
		t.Fatalf("unexpected profile: %+v", p)
	}
	raw, err := os.ReadFile(filepath.Join(a.dir, "session.json"))
	if err != nil {
		t.Fatal(err)
	}
	var saved hgAccountDisk
	if json.Unmarshal(raw, &saved) != nil || saved.Profile.Name != p.Name || saved.Profile.AvatarURL != p.AvatarURL || saved.Profile.UID != p.UID {
		t.Fatal("profile refresh was not durably saved")
	}
}

func TestHongguoProfilePartialResponseKeepsKnownAvatar(t *testing.T) {
	previous := hgAccountProfile{UID: "7000000000000000001", Name: "合成昵称", AvatarURL: "https://avatar.example.test/old.png", PublicID: "7000000000000000002"}
	for _, avatar := range []string{"", "file:///private/account.png", "javascript:alert(1)"} {
		response := map[string]any{"data": map[string]any{"user_info": map[string]any{"avatar_url": avatar, "name": "新合成昵称"}}}
		result := hgMergeProfile(hgProfileData(response), previous)
		if result.Name != "新合成昵称" || result.AvatarURL != previous.AvatarURL || result.PublicID != previous.PublicID || result.UID != previous.UID {
			t.Fatal("partial profile cleared known identity or avatar")
		}
	}
}

func TestHongguoProfileRejectsDifferentAccountWithoutChangingHistory(t *testing.T) {
	_, a := historyFixtureAccount(t, func(r *http.Request) (*http.Response, error) {
		return historyFixtureJSON(t, r, map[string]any{"code": 0, "data": map[string]any{"req_id": "7000000000000000009", "user_name": "其他合成账号", "avatar_url": "https://avatar.example.test/other.png"}}), nil
	})
	a.disk.Profile.Name = "原合成昵称"
	watch := historyFixtureWatch("7000000000000000002", "7000000000000000003")
	a.library.Pending[watch.Drama.ID] = watch
	if a.refreshProfile(context.Background(), a.disk.Profile.UID) == nil {
		t.Fatal("different profile accepted")
	}
	if a.disk.Profile.Name != "原合成昵称" || len(a.library.Pending) != 1 || a.profileError == "" {
		t.Fatal("profile failure changed account or pending history")
	}
}
