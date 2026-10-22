package core

import (
	"context"
	"errors"
	"net/http"
	"net/url"
	"strings"
	"time"
)

func (c *hgAccountHTTP) favoriteIDs(ctx context.Context, uid string) ([]string, error) {
	p, err := c.json(ctx, "/reading/bookapi/bookshelf/video/list/v", http.MethodGet, url.Values{"target_user_id": {uid}}, nil, false)
	if err != nil {
		return nil, err
	}
	data := nestedMap(p, "data")
	rows, ok := data["video_shelf_info"].([]any)
	if !ok || len(rows) > 20000 {
		return nil, errors.New("账号追剧列表格式无效")
	}
	if value, exists := data["has_more"]; exists {
		more, err := hgPageFlag(value)
		if err != nil || more {
			return nil, errors.New("账号追剧列表未完整读取，请稍后重试")
		}
	}
	ids := []string{}
	seen := map[string]bool{}
	for _, row := range rows {
		id := mapString(nestedMap(row), "series_id")
		if !hgValidID(id) {
			return nil, errors.New("账号追剧包含无效剧集身份")
		}
		if !seen[id] {
			ids = append(ids, id)
			seen[id] = true
		}
	}
	return ids, nil
}
func (c *hgAccountHTTP) favoriteMetadata(ctx context.Context, ids []string) (map[string]nativeDrama, error) {
	p, err := c.json(ctx, "/novel/player/multi_video_detail/preload/v1", http.MethodPost, nil,
		map[string]any{"dr_scene": "preload", "series_id": strings.Join(ids, ","), "biz_param": map[string]any{"detail_page_version": 0, "disable_digg_stat": false, "disable_video_relate_book": false, "need_all_video_definition": false, "need_mp4_align": false, "source": 7, "use_os_player": false, "use_server_dns": false}}, false)
	if err != nil {
		return nil, err
	}
	data := nestedMap(p, "data")
	out := map[string]nativeDrama{}
	for _, id := range ids {
		v := nestedMap(data, id, "video_data")
		if len(v) == 0 || mapString(v, "series_title") == "" {
			continue
		}
		if mapString(v, "series_id", "series_id_str", "book_id") != id {
			return nil, errors.New("账号追剧资料身份不一致")
		}
		d := nativeNormalize(hongguoDramaFromAny(v, ""))
		d.ID, d.Source, d.SourceID = providerDramaID(sourceHongguo, id), sourceHongguo, id
		out[id] = d
	}
	return out, nil
}
func (a *hgOfficialAccount) favorites(ctx context.Context, command string, input hgAccountInput) (any, error) {
	if err := a.requireOwner(input.UID); err != nil {
		return nil, err
	}
	ctx, c, generation, finish, err := a.begin(ctx)
	if err != nil {
		return nil, err
	}
	defer finish()
	if err = a.requireOwner(input.UID); err != nil {
		return nil, err
	}
	if command == "favorite" {
		if !hgValidID(input.ID) {
			return nil, errors.New("追剧身份无效")
		}
		operation := 1
		if input.Followed {
			operation = 0
		}
		_, err = c.json(ctx, "/reading/bookapi/bookshelf/video/update/v", http.MethodPost, nil,
			map[string]any{"is_cancelled": false, "shark_extra": map[string]any{"enter_from": "0", "previous_page": "0", "page_list": "0", "is_active_behavior": "1", "inactive_type": "0"}, "update_bookshelf_video_list": []any{map[string]any{"book_id": input.ID, "book_type": 2, "modify_time": time.Now().UnixMilli(), "video_shelf_operate_type": operation}}}, false)
		if err != nil {
			return nil, err
		}
	}
	ids, err := c.favoriteIDs(ctx, input.UID)
	if err != nil {
		return nil, err
	}
	if command == "favorite" {
		found := false
		for _, id := range ids {
			if id == input.ID {
				found = true
				break
			}
		}
		if found != input.Followed {
			return nil, errors.New("云端尚未确认追剧操作，请刷新片单")
		}
	}
	if err = a.persistClient(ctx, c, generation); err != nil {
		return nil, err
	}
	if command == "favorite" {
		return map[string]any{"id": input.ID, "followed": input.Followed, "confirmed": true}, nil
	}
	a.mu.Lock()
	known := map[string]nativeDrama{}
	for _, d := range a.library.Favorites {
		known[d.SourceID] = d
	}
	for _, w := range a.library.History {
		known[w.Drama.SourceID] = w.Drama
	}
	a.mu.Unlock()
	missing := []string{}
	for _, id := range ids {
		if known[id].Title == "" || known[id].Title == "剧集信息暂未加载" {
			missing = append(missing, id)
		}
	}
	warning := ""
	metadataEnd := min(len(missing), 100)
	if len(missing) > metadataEnd {
		warning = "部分追剧资料暂未加载，可继续刷新补齐"
	}
	for start := 0; start < metadataEnd; start += 20 {
		cards, e := c.favoriteMetadata(ctx, missing[start:min(start+20, metadataEnd)])
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		if e != nil {
			warning = "部分追剧资料暂未加载，可刷新重试"
			continue
		}
		for id, d := range cards {
			known[id] = d
		}
	}
	dramas := []nativeDrama{}
	rows := []map[string]any{}
	for _, id := range ids {
		d := known[id]
		if d.ID == "" {
			d = nativeDrama{ID: providerDramaID(sourceHongguo, id), Source: sourceHongguo, SourceID: id, Title: "剧集信息暂未加载"}
		}
		dramas = append(dramas, d)
		rows = append(rows, map[string]any{"id": id, "drama": d, "followed": true})
	}
	if err = a.persistClient(ctx, c, generation); err != nil {
		return nil, err
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	if ctx.Err() != nil || a.generation != generation || a.disk.Profile == nil || a.disk.Profile.UID != input.UID {
		return nil, errors.New("账号已变更，请重新打开片单")
	}
	library := hgCopyLibrary(a.library)
	library.Favorites = dramas
	if err = a.saveLibrary(library); err != nil {
		return nil, errors.New("账号追剧缓存尚未保存")
	}
	a.library = library
	return map[string]any{"items": rows, "warning": warning}, nil
}
