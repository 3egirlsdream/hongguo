package core

import "testing"

func TestHongguoFavoriteCountMetadata(t *testing.T) {
	drama := hongguoDramaFromAny(map[string]any{"series_id": "123", "followed_cnt": "265000", "digg_cnt": "99", "series_play_cnt": "1000000"}, "短剧")
	if drama.FavoriteCount != "265000" || drama.Views != "1000000" {
		t.Fatal("favorite and play counts mixed")
	}
	normalized := nativeNormalize(drama)
	if normalized.FavoriteCount != "265000" {
		t.Fatal("favorite count missing in bridge")
	}
	if mergeNativeDrama(normalized, nativeDrama{ID: normalized.ID}).FavoriteCount != "265000" {
		t.Fatal("cached count lost")
	}
	if mergeDramaMetadata(Drama{}, drama).FavoriteCount != "265000" {
		t.Fatal("detail count lost")
	}
}
