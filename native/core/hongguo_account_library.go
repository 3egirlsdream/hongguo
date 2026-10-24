package core

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
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
