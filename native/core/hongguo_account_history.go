package core

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"time"
)

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

func hgHistoryWatch(row map[string]any) (hgOfficialWatch, error) {
	sid := mapString(row, "book_id_str", "series_id_str", "book_id", "series_id")
	if !hgValidID(sid) {
		return hgOfficialWatch{}, errors.New("红果历史包含无效剧集身份")
	}
	episode := int(hgFloat(row["vid_index"])) + 1
	if chapter := int(hgFloat(row["chapter_index"])); chapter > 0 {
		episode = chapter
	}
	stamp := hgEpoch(row["read_timestamp_ms"])
	position := hgFloat(row["current_play_position"]) / 1000
	if episode < 1 || episode > 1000000 || math.IsNaN(position) || math.IsInf(position, 0) || position < 0 || position > 604800 {
		return hgOfficialWatch{}, errors.New("红果历史包含无效观看进度")
	}
	count := int(hgFloat(row["episode_cnt"]))
	if count == 0 {
		count = int(hgFloat(row["episode_count"]))
	}
	if count > 0 && episode > count {
		episode = count
	}
	return hgOfficialWatch{
		Drama:   nativeDrama{ID: providerDramaID(sourceHongguo, sid), Source: sourceHongguo, SourceID: sid, Title: mapString(row, "book_name", "series_name"), Cover: mapString(row, "thumb_url"), Episodes: count},
		VideoID: mapString(row, "vid_str", "vid", "item_id"), Episode: episode, Position: position, Duration: hgFloat(row["duration"]) / 1000, UpdatedAt: stamp,
	}, nil
}

func (c *hgAccountHTTP) history(ctx context.Context) (map[string]hgOfficialWatch, error) {
	out := map[string]hgOfficialWatch{}
	offset := 0
	seenOffsets := map[int]bool{}
	for page := 0; page < 200; page++ {
		if seenOffsets[offset] {
			return nil, errors.New("红果历史分页游标重复，请刷新重试")
		}
		seenOffsets[offset] = true
		p, err := c.historyPage(ctx, url.Values{"limit": {"0"}, "offset": {strconv.Itoa(offset)}, "book_type": {"2"}, "full_field": {"false"}, "query_soft_deleted": {"false"}, "last_min_read_timestamp_ms": {"0"}, "is_first_load": {strconv.FormatBool(offset == 0)}})
		if err != nil {
			return nil, err
		}
		data := nestedMap(p, "data")
		rows, ok := data["data_list"].([]any)
		if !ok {
			return nil, errors.New("红果历史响应缺少记录列表")
		}
		more, err := hgPageFlag(data["has_more"])
		if err != nil {
			return nil, err
		}
		for _, value := range rows {
			row := nestedMap(value)
			if kind := mapString(row, "book_type"); kind != "" && kind != "2" {
				continue
			}
			if hgBool(row["is_delete"]) {
				continue
			}
			watch, err := hgHistoryWatch(row)
			if err != nil {
				return nil, err
			}
			if old, exists := out[watch.Drama.ID]; !exists || !old.UpdatedAt.After(watch.UpdatedAt) {
				out[watch.Drama.ID] = watch
			}
		}
		if !more {
			return out, nil
		}
		if len(rows) == 0 || page == 199 {
			return nil, errors.New("红果历史分页未完成，请稍后重试")
		}
		next := int(hgFloat(data["next_offset"]))
		if _, exists := data["next_offset"]; !exists {
			next = offset + 500
		}
		if next <= offset {
			return nil, errors.New("红果历史分页没有前进，请刷新重试")
		}
		offset = next
	}
	return nil, errors.New("红果历史分页未完成")
}

func hgCheckHistoryUpdate(response map[string]any) error {
	for _, data := range []map[string]any{response, nestedMap(response, "data")} {
		if value, ok := data["update_fail_datas"]; ok && value != nil {
			failed, valid := value.([]any)
			if !valid {
				return errors.New("红果历史上传确认格式无效，记录仍保留在队列")
			}
			if len(failed) > 0 {
				return fmt.Errorf("红果拒绝了 %d 条历史记录，待上传进度保留", len(failed))
			}
		}
	}
	return nil
}

func (c *hgAccountHTTP) uploadWatch(ctx context.Context, w hgOfficialWatch) error {
	sid := w.Drama.SourceID
	if sid == "" {
		_, sid, _ = splitProviderDramaID(w.Drama.ID)
	}
	if !hgValidID(sid) || !hgValidID(w.VideoID) || w.Episode < 1 {
		return errors.New("待同步进度缺少剧集或分集身份")
	}
	stamp := w.UpdatedAt.UnixMilli()
	position, duration := int64(w.Position*1000), int64(w.Duration*1000)
	row := map[string]any{"book_id": json.Number(sid), "book_type": 2, "vid": json.Number(w.VideoID), "vid_index": w.Episode - 1, "chapter_index": 0, "current_play_position": position, "player_accumulate_total_time": position, "read_timestamp_ms": stamp, "update_timestamp_ms": stamp, "is_delete": false, "is_interactive_game": false, "is_listen_mode": false, "is_multi_season": 0, "season_index": 0, "duration": duration, "episode_cnt": w.Drama.Episodes, "digged_count": 0, "user_digg": false, "origin_novel_book_id": 0, "recent_reads": 0, "retain_video_play_time": 0, "series_play_cnt": 0, "tone_id": 0, "use_soft_delete": false, "meet_guide_comment_tag": false, "user_playlet_comment_flag": false}
	response, err := c.json(ctx, "/reading/bookapi/read_history/update/v", http.MethodPost, nil, map[string]any{"update_datas": []any{row}}, true)
	if err != nil {
		return err
	}
	if err = hgCheckHistoryUpdate(response); err != nil {
		return err
	}
	progress := map[string]any{"book_id": sid, "book_type": 2, "item_id": w.VideoID, "vid_index": w.Episode - 1, "current_play_time": position, "player_cumulative_total_duration": position, "read_timestamp_ms": stamp, "progress_type": 0, "channel_id": 0, "cur_channel_id": 0, "check_timestamp": false, "is_listen_mode": false, "is_local_book": false, "listen_and_read": false, "page_index": 0, "page_progress_rate": 0, "paragraph_offset": 0, "tone_id": 0}
	response, err = c.json(ctx, "/reading/bookapi/read_progress/upload/v", http.MethodPost, nil, map[string]any{"books": []any{progress}}, true)
	if err != nil {
		return err
	}
	return hgCheckHistoryUpdate(response)
}

func (a *hgOfficialAccount) commitHistory(ctx context.Context, c *hgAccountHTTP, g uint64, uid string, remote, acknowledged map[string]hgOfficialWatch, synced bool, syncErr error) error {
	if err := a.persistClient(ctx, c, g); err != nil {
		return err
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	if ctx.Err() != nil || a.generation != g || a.disk.Profile == nil || a.disk.Profile.UID != uid {
		return errors.New("同步已取消")
	}
	library := hgCopyLibrary(a.library)
	for id, watch := range remote {
		if old, ok := library.History[id]; !ok || watch.UpdatedAt.After(old.UpdatedAt) {
			if old.Drama.ID != "" {
				watch.Drama = mergeNativeDrama(old.Drama, watch.Drama)
			}
			if watch.Drama.Title == "" {
				watch.Drama.Title = "红果短剧 " + watch.Drama.SourceID
			}
			library.History[id] = watch
		}
	}
	for id, watch := range acknowledged {
		if current, ok := library.Pending[id]; ok && current.UpdatedAt.Equal(watch.UpdatedAt) && current.VideoID == watch.VideoID && current.Position == watch.Position && current.Episode == watch.Episode {
			delete(library.Pending, id)
		}
	}
	if synced && syncErr == nil {
		library.LastSync = time.Now().UTC()
	}
	if err := a.saveLibrary(library); err != nil {
		return errors.New("同步结果尚未保存，待上传进度已保留")
	}
	a.library = library
	if synced {
		a.syncError = ""
		if syncErr != nil {
			a.syncError = syncErr.Error()
		}
	}
	return nil
}

func (a *hgOfficialAccount) refreshHistory(ctx context.Context, uid string) error {
	if err := a.requireOwner(uid); err != nil {
		return err
	}
	ctx, c, g, finish, err := a.begin(ctx)
	if err != nil {
		return err
	}
	defer finish()
	if err := a.requireOwner(uid); err != nil {
		return err
	}
	remote, err := c.history(ctx)
	if err != nil {
		return err
	}
	return a.commitHistory(ctx, c, g, uid, remote, nil, false, nil)
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
		defer a.mu.Unlock()
		if a.generation == g {
			a.syncError = ""
			if err != nil {
				a.syncError = err.Error()
			}
		}
	}()
	a.mu.Lock()
	pending := hgCopyLibrary(a.library).Pending
	a.mu.Unlock()
	if len(pending) == 0 {
		var remote map[string]hgOfficialWatch
		remote, err = c.history(ctx)
		if err != nil {
			return err
		}
		return a.commitHistory(ctx, c, g, uid, remote, nil, true, nil)
	}
	watches := []hgOfficialWatch{}
	for _, watch := range pending {
		watches = append(watches, watch)
	}
	sort.Slice(watches, func(i, j int) bool {
		if watches[i].UpdatedAt.Equal(watches[j].UpdatedAt) {
			return watches[i].Drama.ID < watches[j].Drama.ID
		}
		return watches[i].UpdatedAt.After(watches[j].UpdatedAt)
	})
	watches = watches[:min(len(watches), 50)]
	remote, err := c.history(ctx)
	if err != nil {
		return err
	}
	acknowledged := map[string]hgOfficialWatch{}
	uploaded := map[string]hgOfficialWatch{}
	failures := 0
	var firstFailure error
	for _, watch := range watches {
		id := watch.Drama.ID
		if newer, ok := remote[id]; ok && newer.UpdatedAt.After(watch.UpdatedAt) {
			acknowledged[id] = watch
			continue
		}
		if err = a.requireOwner(uid); err != nil {
			return err
		}
		if uploadErr := c.uploadWatch(ctx, watch); uploadErr != nil {
			failures++
			if firstFailure == nil {
				firstFailure = uploadErr
			}
			if ctx.Err() != nil {
				break
			}
			continue
		}
		uploaded[id] = watch
	}
	if len(uploaded) > 0 && ctx.Err() == nil {
		confirmed, readErr := c.confirmHistory(ctx, uploaded, hgHistoryPause)
		if readErr != nil && firstFailure == nil {
			firstFailure = readErr
		}
		for id, watch := range uploaded {
			cloud := confirmed[id]
			if !hgWatchConfirmed(cloud, watch) {
				failures++
				continue
			}
			acknowledged[id] = watch
			remote[id] = cloud
		}
	}

	var failure error
	if failures > 0 {
		failure = fmt.Errorf("%d 条历史尚未得到云端确认，未确认记录保留待重试", failures)
		if firstFailure != nil {
			failure = fmt.Errorf("%w：%v", failure, firstFailure)
		}
	}
	if ctx.Err() != nil {
		return ctx.Err()
	}
	if err = a.commitHistory(ctx, c, g, uid, remote, acknowledged, true, failure); err != nil {
		return err
	}
	return failure
}

func hgWatchConfirmed(cloud, local hgOfficialWatch) bool {
	return local.Drama.ID != "" && cloud.VideoID == local.VideoID && cloud.UpdatedAt.Compare(local.UpdatedAt.Add(-time.Second)) >= 0 && cloud.Position+.001 >= local.Position
}

func hgHistoryPause(ctx context.Context, delay time.Duration) error {
	if delay <= 0 {
		return ctx.Err()
	}
	timer := time.NewTimer(delay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}

func (c *hgAccountHTTP) confirmHistory(ctx context.Context, uploaded map[string]hgOfficialWatch, pause func(context.Context, time.Duration) error) (map[string]hgOfficialWatch, error) {
	confirmed := map[string]hgOfficialWatch{}
	var readErr error
	for _, delay := range []time.Duration{0, 2 * time.Second, 4 * time.Second, 8 * time.Second, 16 * time.Second} {
		if err := pause(ctx, delay); err != nil {
			return confirmed, err
		}
		rows, err := c.history(ctx)
		readErr = err
		if err != nil {
			continue
		}
		for id, watch := range uploaded {
			if hgWatchConfirmed(rows[id], watch) {
				confirmed[id] = rows[id]
			}
		}
		if len(confirmed) == len(uploaded) {
			return confirmed, nil
		}
	}
	return confirmed, readErr
}

func (c *hgAccountHTTP) historyPage(ctx context.Context, query url.Values) (map[string]any, error) {
	var result map[string]any
	var err error
	for _, delay := range []time.Duration{0, 250 * time.Millisecond, 750 * time.Millisecond} {
		if err = hgHistoryPause(ctx, delay); err != nil {
			return nil, err
		}
		result, err = c.json(ctx, "/reading/bookapi/read_history/list/v", http.MethodGet, query, nil, false)
		if err == nil {
			return result, nil
		}
		var rejected *hgAccountAPIError
		if !errors.As(err, &rejected) || rejected.Code != "100103" {
			return nil, err
		}
	}
	return nil, err
}
