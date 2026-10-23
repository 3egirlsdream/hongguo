package core

import (
	"context"
	"encoding/json"
	"errors"
	"math"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"
)

func hgBool(v any) bool {
	switch x := v.(type) {
	case bool:
		return x
	case string:
		return x == "true" || x == "1"
	case json.Number:
		return x == "1"
	case float64:
		return x == 1
	}
	return false
}

func hgPageFlag(v any) (bool, error) {
	switch value := v.(type) {
	case bool:
		return value, nil
	case json.Number:
		if value == "0" || value == "1" {
			return value == "1", nil
		}
	case string:
		if value == "true" || value == "false" || value == "0" || value == "1" {
			return value == "true" || value == "1", nil
		}
	}
	return false, errors.New("红果分页状态无效")
}
func hgFloat(v any) float64 {
	n, _ := strconv.ParseFloat(mapString(map[string]any{"value": v}, "value"), 64)
	return n
}
func hgEpoch(v any) time.Time {
	n := int64(hgFloat(v))
	if n <= 0 {
		return time.Time{}
	}
	if n < 100000000000 {
		n *= 1000
	}
	return time.UnixMilli(n).UTC()
}
func (a *hgOfficialAccount) queueProgress(input hgAccountInput) error {
	w := input.Watch
	if !nativeDramaAvailable(w.Drama) || !hgValidID(w.VideoID) || w.Episode < 1 || w.Episode > 1000000 || math.IsNaN(w.Position) || math.IsInf(w.Position, 0) || w.Position < 0 || w.Position > 604800 || math.IsNaN(w.Duration) || math.IsInf(w.Duration, 0) || w.Duration < 0 || w.Duration > 604800 || w.UpdatedAt.Year() < 2000 || w.UpdatedAt.After(time.Now().Add(5*time.Minute)) {
		return errors.New("红果观看进度无效")
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.disk.Profile == nil || input.UID != a.disk.Profile.UID {
		return errors.New("红果账号已变更，进度保留在本地")
	}
	id := w.Drama.ID
	l := hgCopyLibrary(a.library)
	if old, ok := l.History[id]; ok && old.UpdatedAt.After(w.UpdatedAt) {
		return nil
	}
	if len(l.Pending) >= 2000 {
		if _, ok := l.Pending[id]; !ok {
			return errors.New("待同步进度已达上限，请先同步")
		}
	}
	l.History[id], l.Pending[id] = w, w
	if e := a.saveLibrary(l); e != nil {
		return errors.New("红果待同步进度尚未保存")
	}
	a.library = l
	return nil
}
func (c *hgAccountHTTP) history(ctx context.Context) (map[string]hgOfficialWatch, error) {
	out := map[string]hgOfficialWatch{}
	offset := 0
	for page := 0; page < 200; page++ {
		p, e := c.json(ctx, "/reading/bookapi/read_history/list/v", http.MethodGet, url.Values{"limit": {"0"}, "offset": {strconv.Itoa(offset)}, "book_type": {"2"}, "full_field": {"false"}, "query_soft_deleted": {"false"}, "last_min_read_timestamp_ms": {"0"}, "is_first_load": {strconv.FormatBool(offset == 0)}}, nil, false)
		if e != nil {
			return nil, e
		}
		d := nestedMap(p, "data")
		rows, ok := d["data_list"].([]any)
		if !ok {
			return nil, errors.New("红果历史响应缺少记录列表")
		}
		if _, ok = d["has_more"]; !ok {
			return nil, errors.New("红果历史响应缺少分页状态")
		}
		added := 0
		for _, v := range rows {
			r := nestedMap(v)
			if bt := mapString(r, "book_type"); bt != "" && bt != "2" {
				continue
			}
			sid := mapString(r, "book_id", "series_id")
			if !hgValidID(sid) {
				return nil, errors.New("红果历史包含无效剧集身份")
			}
			id := providerDramaID(sourceHongguo, sid)
			if _, exists := out[id]; !exists {
				added++
			}
			episode := int(hgFloat(r["vid_index"]))
			if episode < 1 {
				continue
			}
			w := hgOfficialWatch{Drama: nativeDrama{ID: id, Source: sourceHongguo, SourceID: sid, Title: firstNonEmpty(mapString(r, "book_name", "series_name"), "红果短剧 "+sid), Cover: mapString(r, "thumb_url"), Episodes: int(hgFloat(r["episode_cnt"]))}, VideoID: mapString(r, "vid"), Episode: episode, Position: hgFloat(r["current_play_position"]) / 1000, Duration: hgFloat(r["duration"]) / 1000, UpdatedAt: hgEpoch(r["read_timestamp_ms"])}
			if old, exists := out[id]; !exists || w.UpdatedAt.After(old.UpdatedAt) {
				out[id] = w
			}
		}
		more, e := hgPageFlag(d["has_more"])
		if e != nil {
			return nil, e
		}
		if !more {
			break
		}
		if len(rows) == 0 || added == 0 || page == 199 {
			return nil, errors.New("红果历史分页未完成，请稍后重试")
		}
		next := int(hgFloat(d["next_offset"]))
		if next <= offset {
			next = offset + 500
		}
		offset = next
	}
	ids := []string{}
	for _, w := range out {
		ids = append(ids, w.Drama.SourceID)
	}
	sort.Strings(ids)
	for start := 0; start < len(ids); start += 200 {
		batch := []json.Number{}
		for _, id := range ids[start:min(start+200, len(ids))] {
			batch = append(batch, json.Number(id))
		}
		p, e := c.json(ctx, "/reading/bookapi/read_progress/get/v", http.MethodPost, nil, map[string]any{"book_ids": map[string]any{"2": batch}}, false)
		if e != nil {
			return nil, e
		}
		rows, ok := p["video_data"].([]any)
		if !ok {
			rows, ok = nestedMap(p, "data")["video_data"].([]any)
		}
		if !ok {
			return nil, errors.New("红果观看进度响应缺少列表")
		}
		for _, v := range rows {
			r := nestedMap(v)
			id := providerDramaID(sourceHongguo, mapString(r, "series_id", "book_id"))
			w, exists := out[id]
			if !exists {
				continue
			}
			stamp := hgEpoch(r["last_watch_time"])
			episode := int(hgFloat(r["vid_index"]))
			if episode > 0 && stamp.After(w.UpdatedAt) {
				if episode != w.Episode {
					w.Position, w.Duration, w.VideoID = 0, 0, ""
				}
				w.Episode, w.UpdatedAt = episode, stamp
				if p, exists := r["current_play_time"]; exists {
					w.Position = hgFloat(p) / 1000
				}
				if vid := mapString(r, "item_id", "vid"); hgValidID(vid) {
					w.VideoID = vid
				}
				out[id] = w
			}
		}
	}
	return out, nil
}
func (c *hgAccountHTTP) uploadWatch(ctx context.Context, w hgOfficialWatch) error {
	sid := w.Drama.SourceID
	if sid == "" {
		_, sid, _ = splitProviderDramaID(w.Drama.ID)
	}
	if !hgValidID(sid) || !hgValidID(w.VideoID) {
		return errors.New("待同步进度缺少剧集或分集身份")
	}
	stamp := w.UpdatedAt.UnixMilli()
	position, duration := int64(w.Position*1000), int64(w.Duration*1000)
	row := map[string]any{"book_id": json.Number(sid), "book_type": 2, "vid": json.Number(w.VideoID), "vid_index": w.Episode, "chapter_index": 0, "current_play_position": position, "player_accumulate_total_time": position, "read_timestamp_ms": stamp, "update_timestamp_ms": stamp, "is_delete": false, "is_interactive_game": false, "is_listen_mode": false, "is_multi_season": false, "season_index": 0, "duration": duration, "episode_cnt": w.Drama.Episodes, "digged_count": 0, "user_digg": false, "origin_novel_book_id": 0, "recent_reads": 0, "retain_video_play_time": 0, "series_play_cnt": 0, "tone_id": 0, "use_soft_delete": false, "meet_guide_comment_tag": false, "user_playlet_comment_flag": false}
	if _, e := c.json(ctx, "/reading/bookapi/read_history/update/v", http.MethodPost, nil, map[string]any{"update_datas": []any{row}}, false); e != nil {
		return e
	}
	progress := map[string]any{"book_id": sid, "book_type": 2, "item_id": w.VideoID, "vid_index": w.Episode, "current_play_time": position, "player_cumulative_total_duration": position, "read_timestamp_ms": stamp, "progress_type": 0, "channel_id": 0, "cur_channel_id": 0, "check_timestamp": false, "is_listen_mode": false, "is_local_book": false, "listen_and_read": false, "page_index": 0, "page_progress_rate": 0, "paragraph_offset": 0, "tone_id": 0}
	_, e := c.json(ctx, "/reading/bookapi/read_progress/upload/v", http.MethodPost, nil, map[string]any{"books": []any{progress}}, false)
	return e
}
func (a *hgOfficialAccount) syncHistory(ctx context.Context, uid string) (err error) {
	if err = a.requireOwner(uid); err != nil {
		return err
	}
	ctx, c, g, finish, err := a.begin(ctx)
	if err != nil {
		return err
	}
	defer finish()
	if err = a.requireOwner(uid); err != nil {
		return err
	}
	defer func() {
		a.mu.Lock()
		if a.generation == g {
			a.syncError = ""
			if err != nil {
				a.syncError = err.Error()
			}
		}
		a.mu.Unlock()
	}()
	remote, err := c.history(ctx)
	if err != nil {
		return err
	}
	if err = a.requireOwner(uid); err != nil {
		return err
	}
	a.mu.Lock()
	pending := hgCopyLibrary(a.library).Pending
	a.mu.Unlock()
	acknowledged := map[string]hgOfficialWatch{}
	for id, w := range pending {
		if r, ok := remote[id]; ok && r.UpdatedAt.After(w.UpdatedAt) {
			acknowledged[id] = w
			continue
		}
		if err = c.uploadWatch(ctx, w); err != nil {
			return err
		}
		acknowledged[id] = w
		if old, ok := remote[id]; !ok || w.UpdatedAt.After(old.UpdatedAt) {
			remote[id] = w
		}
	}
	if err = a.persistClient(ctx, c, g); err != nil {
		return err
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	if ctx.Err() != nil || a.generation != g || a.disk.Profile == nil || a.disk.Profile.UID != uid {
		return errors.New("同步已取消")
	}
	l := hgCopyLibrary(a.library)
	for id, w := range remote {
		if old, ok := l.History[id]; !ok || w.UpdatedAt.After(old.UpdatedAt) {
			l.History[id] = w
		}
	}
	for id, w := range acknowledged {
		if current, ok := l.Pending[id]; ok && current.UpdatedAt.Equal(w.UpdatedAt) && current.VideoID == w.VideoID && current.Position == w.Position {
			delete(l.Pending, id)
		}
	}
	l.LastSync = time.Now().UTC()
	if err = a.saveLibrary(l); err != nil {
		return errors.New("同步结果尚未保存，待上传进度已保留")
	}
	a.library = l
	return nil
}

type hgReservation struct {
	ID          string      `json:"id"`
	Drama       nativeDrama `json:"drama"`
	Reserved    bool        `json:"reserved"`
	Upcoming    bool        `json:"upcoming"`
	PublishText string      `json:"publishText"`
}

func (c *hgAccountHTTP) reservationPage(ctx context.Context, mode string, offset int, cursor string, calendar bool, subscribeOffset *int) (map[string]any, error) {
	if offset < 0 || offset > 100000 || len(cursor) > 4096 || strings.ContainsAny(cursor, "\r\n\x00") {
		return nil, errors.New("预约分页无效")
	}
	q := url.Values{"offset": {strconv.Itoa(offset)}, "subscribe_offset": {"0"}}
	if calendar {
		q.Set("tab_type", "5")
		q.Set("tab_style", "2")
		q.Set("active_panel", "6")
		q.Set("gender_type", "2")
		q.Set("need_calendar_schema", "true")
		q.Del("subscribe_offset")
		if subscribeOffset != nil {
			if *subscribeOffset < 0 || *subscribeOffset > 100000 {
				return nil, errors.New("预约分页无效")
			}
			q.Set("subscribe_offset", strconv.Itoa(*subscribeOffset))
		}
		if mode != "" {
			if _, e := time.Parse("20060102", mode); e != nil {
				return nil, errors.New("上新日期无效")
			}
			q.Set("target_date", mode)
		}
	} else {
		q.Set("tab_type", "13")
		q.Set("subscribe_order_type", "0")
		q.Set("swipe_type", "0")
		q.Set("need_calendar_schema", "false")
		q.Set("limit", "20")
		q.Set("is_online", strconv.FormatBool(mode != "upcoming"))
	}
	if cursor != "" {
		q.Set("session_id", cursor)
	}
	p, e := c.json(ctx, "/reading/user/subscribe/list/v1/", http.MethodGet, q, nil, false)
	if e != nil {
		return nil, e
	}
	d := nestedMap(p, "data")
	rows, ok := d["subscribe_items"].([]any)
	if !ok {
		return nil, errors.New("红果预约响应缺少列表")
	}
	items := []hgReservation{}
	for _, v := range rows {
		r := nestedMap(v)
		sub := nestedMap(r, "subscribe_data")
		sid := mapString(sub, "series_id_str", "series_id")
		if !hgValidID(sid) {
			sid = mapString(r, "item_id")
		}
		if !hgValidID(sid) {
			continue
		}
		drama := nativeNormalize(hongguoDramaFromAny(sub, ""))
		drama.ID, drama.Source, drama.SourceID = providerDramaID(sourceHongguo, sid), sourceHongguo, sid
		drama.Title = firstNonEmpty(mapString(sub, "series_title", "series_name", "title"), mapString(r, "name"), "红果短剧 "+sid)
		if drama.Cover == "" {
			drama.Cover = mapString(r, "cover")
		}
		publishText := hongguoPublishText(time.Now(), r, sub)
		items = append(items, hgReservation{ID: sid, Drama: drama, Reserved: !calendar || hgBool(r["has_subscribed"]), Upcoming: !hgBool(r["is_online"]), PublishText: publishText})
	}
	more, flagError := hgPageFlag(d["has_more"])
	if flagError != nil {
		return nil, flagError
	}
	next := int(hgFloat(d["next_offset"]))
	var nextSubscribe *int
	if calendar {
		location := nestedMap(d, "calendar_loc_info")
		more = more || hgBool(location["down_has_more"])
		if v, ok := location["subscribe_offset"]; ok {
			n := int(hgFloat(v))
			if n >= 0 {
				nextSubscribe = &n
			}
		}
	} else if more && next <= offset && len(rows) > 0 {
		next = offset + 20
	}
	advances := next > offset
	if calendar && nextSubscribe != nil {
		advances = advances || subscribeOffset == nil || *nextSubscribe > *subscribeOffset
	}
	if more && (len(rows) == 0 || !advances) {
		return nil, errors.New("红果预约分页没有前进，请刷新重试")
	}
	result := map[string]any{"items": items, "hasMore": more, "offset": next, "cursor": mapString(d, "session_id")}
	if nextSubscribe != nil {
		result["subscribeOffset"] = *nextSubscribe
	}
	return result, nil
}
func (a *hgOfficialAccount) reservations(ctx context.Context, command string, input hgAccountInput) (any, error) {
	if e := a.requireOwner(input.UID); e != nil {
		return nil, e
	}
	ctx, c, g, finish, e := a.begin(ctx)
	if e != nil {
		return nil, e
	}
	defer finish()
	if e = a.requireOwner(input.UID); e != nil {
		return nil, e
	}
	if command != "reserve" {
		result, e := c.reservationPage(ctx, input.Mode, input.Offset, input.Cursor, command == "calendar", input.SubscribeOffset)
		if e != nil {
			return nil, e
		}
		if e = a.persistClient(ctx, c, g); e != nil {
			return nil, e
		}
		return result, nil
	}
	if !hgValidID(input.ID) {
		return nil, errors.New("预约剧集身份无效")
	}
	op := 2
	if input.Reserved {
		op = 1
	}
	_, e = c.json(ctx, "/reading/bookapi/search/uncover_subscribe/v", http.MethodPost, nil, map[string]any{"item_id": json.Number(input.ID), "item_type": 1, "op_type": op, "wish_list_all_del": 0, "shark_param": map[string]any{"enter_from": "BulletActivity", "previous_page": "MainFragmentActivity", "page_list": "MainFragmentActivity,BulletActivity"}}, true)
	if e != nil {
		return nil, e
	}
	found := false
	for _, mode := range []string{"online", "upcoming"} {
		offset := 0
		cursor := ""
		for page := 0; page < 100; page++ {
			result, e := c.reservationPage(ctx, mode, offset, cursor, false, nil)
			if e != nil {
				return nil, errors.New("预约请求已发送，但暂不能确认是否生效，请刷新官方预约列表")
			}
			for _, row := range result["items"].([]hgReservation) {
				if row.ID == input.ID {
					found = true
				}
			}
			if !result["hasMore"].(bool) {
				break
			}
			if page == 99 {
				return nil, errors.New("官方预约列表尚未读完，暂不能确认是否生效")
			}
			offset = result["offset"].(int)
			cursor = result["cursor"].(string)
		}
	}
	if e = a.persistClient(ctx, c, g); e != nil {
		return nil, e
	}
	if found != input.Reserved {
		return nil, errors.New("红果官方列表尚未确认预约状态，请稍后刷新")
	}
	return map[string]any{"id": input.ID, "reserved": found, "confirmed": true}, nil
}
