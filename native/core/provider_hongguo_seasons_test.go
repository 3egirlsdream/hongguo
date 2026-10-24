package core

import (
	"encoding/json"
	"testing"
)

func TestHongguoOfficialSeasonsUseTagsAndSeasonNumbers(t *testing.T) {
	var result map[string]any
	if err := json.Unmarshal([]byte(`{"code":0,"data":[{"cell_name":"猜你喜欢","video_data":[{"series_id":"99","title":"other","episode_cnt":10,"tag_info":{"text":"第4季"}}]},{"cell_name":"相关作品","video_data":[{"series_id":"5","title":"future","season_index":5,"episode_cnt":0,"online_subscribed":false,"tag_info":{"text":"第5季"}},{"series_id":"88","title":"other IP","season_index":4,"episode_cnt":99,"tag_info":{"text":"同IP"}},{"series_id":"4","title":"next","season_index":4,"episode_cnt":330,"tag_info":{"text":"第4季"}},{"series_id":"1","title":"first","episode_cnt":125,"tag_info":{"text":"第1季"}},{"series_id":"6","title":"unknown release","episode_cnt":0,"tag_info":{"text":"第6季"}}]}]}`), &result); err != nil {
		t.Fatal(err)
	}
	current := nativeDrama{ID: "hongguo:3", Source: "hongguo", SourceID: "3", Title: "current", Episodes: 320}
	response, err := parseHongguoOfficialSeasons(result, current, 3)
	if err != nil {
		t.Fatal(err)
	}
	if response.CurrentSeason != 3 || len(response.Seasons) != 5 {
		t.Fatalf("unexpected seasons: %+v", response)
	}
	next := []hongguoOfficialSeason{}
	for _, season := range response.Seasons {
		if season.Drama.ID == "hongguo:88" || season.Drama.ID == "hongguo:99" {
			t.Fatal("unrelated work included")
		}
		if season.Next {
			next = append(next, season)
		}
		if season.Number == 5 && (!season.Reservable || season.Playable) {
			t.Fatal("upcoming reservation mapping")
		}
		if season.Number == 6 && (!season.Reservable || season.Playable) {
			t.Fatal("missing reservation state must not hide an upcoming season")
		}
	}
	if len(next) != 1 || next[0].Number != 4 || !next[0].Playable {
		t.Fatalf("wrong next season: %+v", next)
	}
}

func TestHongguoOfficialSeasonsRejectMalformedOrUnconfirmedResponse(t *testing.T) {
	current := nativeDrama{ID: "hongguo:3", SourceID: "3", Episodes: 10}
	for _, result := range []map[string]any{{"data": []any{}}, {"code": 1, "data": []any{}}, {"code": 0, "data": map[string]any{}}} {
		if _, err := parseHongguoOfficialSeasons(result, current, 3); err == nil {
			t.Fatal("invalid response accepted")
		}
	}
	response, err := parseHongguoOfficialSeasons(map[string]any{"code": 0, "data": []any{}}, current, 0)
	if err != nil || len(response.Seasons) != 0 {
		t.Fatal("unknown current season must remain unknown")
	}
}
