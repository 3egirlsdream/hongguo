package core

import (
	"context"
	"errors"
	"net/http"
	"net/url"
	"strconv"
	"strings"
)

type hongguoRecommendationQuery struct {
	Genre     string   `json:"genre"`
	Offset    int      `json:"offset"`
	SessionID string   `json:"sessionId"`
	Seen      []string `json:"seen"`
}

type hongguoRecommendationPage struct {
	Dramas     []Drama `json:"data"`
	NextOffset int     `json:"nextOffset"`
	SessionID  string  `json:"sessionId"`
	HasMore    bool    `json:"hasMore"`
	Saved      bool    `json:"saved"`
}

func (query hongguoRecommendationQuery) validate() error {
	known := query.Genre == "feed"
	for _, genre := range hongguoAppGenres {
		known = known || query.Genre == genre.key
	}
	if !known || query.Offset < 0 || query.Offset > 1_000_000 || len(query.SessionID) > 4096 || strings.ContainsAny(query.SessionID, "\r\n\x00") || len(query.Seen) > 540 {
		return errors.New("推荐分类或分页参数无效，请重新获取")
	}
	for _, id := range query.Seen {
		if !hongguoNumericID.MatchString(strings.TrimPrefix(id, "hongguo:")) {
			return errors.New("推荐分页含无效剧集 ID")
		}
	}
	return nil
}

func (downloader *Downloader) fetchHongguoRecommendations(ctx context.Context, query hongguoRecommendationQuery) (hongguoRecommendationPage, error) {
	page := hongguoRecommendationPage{Dramas: []Drama{}}
	if err := query.validate(); err != nil {
		return page, err
	}
	if query.Genre == "feed" {
		return downloader.fetchHongguoFeedRecommendations(ctx, query)
	}
	scene, category := "", ""
	for _, genre := range hongguoAppGenres {
		if genre.key == query.Genre {
			scene, category = genre.scene, genre.name
		}
	}
	seen := make(map[string]bool, len(query.Seen))
	filterIDs := make([]string, 0, len(query.Seen))
	for _, id := range query.Seen {
		id = strings.TrimPrefix(id, "hongguo:")
		if !seen[id] {
			filterIDs = append(filterIDs, id)
			seen[id] = true
		}
	}
	payload := map[string]any{
		"req_scene": scene, "offset": query.Offset, "limit": 18,
		"req_type": "only_content", "need_selector_panel": false, "client_req_type": 3,
		"session_id": query.SessionID, "filter_ids": strings.Join(filterIDs, ","),
		"select_items": map[string]any{
			"genre": []string{query.Genre}, "sort": []string{}, "gender": []string{},
			"category_dim_theme": []string{}, "category_dim_role": []string{}, "category_dim_epoch": []string{},
			"online_time": []string{}, "creation_status": []string{},
		},
	}
	if query.Offset > 0 {
		payload["client_req_type"] = 2
	}
	result, err := downloader.hongguoAppRequest(ctx, http.MethodPost, "/reading/distribution/category/landpage/v/", nil, payload)
	if err != nil {
		return page, err
	}
	data := nestedMap(result, "data")
	rows, valid := data["video_data"].([]any)
	hasMore, paginationOK := data["has_more"].(bool)
	next, parseErr := strconv.Atoi(mapString(data, "next_offset"))
	if !valid || !paginationOK || hasMore && parseErr != nil {
		return page, errors.New("红果推荐数据格式异常，已保留上次位置")
	}
	validRows := 0
	for _, row := range rows {
		drama := hongguoDramaFromAny(row, category)
		if drama.ID != "" {
			validRows++
		}
		id := strings.TrimPrefix(drama.ID, "hongguo:")
		if drama.ID == "" || seen[id] {
			continue
		}
		seen[id] = true
		page.Dramas = append(page.Dramas, drama)
	}
	if len(rows) > 0 && validRows == 0 {
		return hongguoRecommendationPage{}, errors.New("红果推荐未返回可识别的剧集")
	}
	if hasMore && (next <= query.Offset || next > 1_000_000 || len(page.Dramas) == 0) {
		return hongguoRecommendationPage{}, errors.New("红果推荐分页未前进，可重试或重新获取")
	}
	page.NextOffset, page.HasMore, page.SessionID = next, hasMore, mapString(data, "session_id")
	if !hasMore && (next < query.Offset || next > 1_000_000) {
		page.NextOffset = query.Offset
	}
	if len(page.SessionID) > 4096 || strings.ContainsAny(page.SessionID, "\r\n\x00") {
		return hongguoRecommendationPage{}, errors.New("红果推荐分页标记无效")
	}
	return page, ctx.Err()
}

func (downloader *Downloader) fetchHongguoFeedRecommendations(ctx context.Context, query hongguoRecommendationQuery) (hongguoRecommendationPage, error) {
	seen := map[string]bool{}
	filters := make([]string, 0, len(query.Seen))
	for _, id := range query.Seen {
		id = strings.TrimPrefix(id, "hongguo:")
		if !seen[id] {
			seen[id] = true
			filters = append(filters, id)
		}
	}
	offset, session := query.Offset, query.SessionID
	for attempt := 0; attempt < 3; attempt++ {
		params := url.Values{
			"bottom_tab_type": {"7"}, "client_req_type": {"2"}, "client_template": {"7"},
			"change_type": {"0"}, "category_id": {"0"}, "cell_sub_id": {"0"}, "limit": {"10"},
			"need_personal_recommend": {"1"}, "video_type_preferences_str": {"[]"},
			"cell_id": {"7294257141911650341"}, "plan_id": {"7294257258253254693"}, "tab_type": {"16"},
			"offset": {strconv.Itoa(offset)}, "session_id": {session}, "filter_ids": {strings.Join(filters, ",")},
		}
		result, err := downloader.hongguoAppRequest(ctx, http.MethodGet, "/reading/bookapi/bookmall/cell/change/v", params, nil)
		if err != nil {
			return hongguoRecommendationPage{}, err
		}
		data := nestedMap(result, "data")
		cells, valid := nestedMap(data, "cell_view")["cell_data"].([]any)
		more, flagErr := hgPageFlag(data["has_more"])
		next, nextErr := strconv.Atoi(mapString(data, "next_offset"))
		if !valid || flagErr != nil || more && (nextErr != nil || next <= offset || next > 1_000_000) {
			return hongguoRecommendationPage{}, errors.New("红果官方推荐分页数据异常，已保留上次位置")
		}
		nextSession := mapString(data, "session_id")
		if nextSession == "" {
			nextSession = session
		}
		if len(nextSession) > 4096 || strings.ContainsAny(nextSession, "\r\n\x00") {
			return hongguoRecommendationPage{}, errors.New("红果官方推荐会话无效")
		}
		if !more && (nextErr != nil || next < offset || next > 1_000_000) {
			next = offset
		}
		page := hongguoRecommendationPage{Dramas: []Drama{}, NextOffset: next, SessionID: nextSession, HasMore: more}
		visited := 0
		var collect func([]any, int)
		collect = func(rows []any, depth int) {
			if depth > 6 {
				return
			}
			for _, value := range rows {
				visited++
				if visited > 4096 {
					return
				}
				cell := nestedMap(value)
				if !hgBool(cell["disable_play"]) {
					detail := nestedMap(cell, "video_detail")
					drama := hongguoDramaFromAny(detail, "")
					id := strings.TrimPrefix(drama.ID, "hongguo:")
					count := int(hgFloat(drama.EpisodeCount))
					if drama.ID != "" && count > 0 && !seen[id] {
						seen[id] = true
						page.Dramas = append(page.Dramas, drama)
					}
					collect(anyList(cell["video_data"]), depth+1)
					collect(anyList(cell["cell_data"]), depth+1)
				}
			}
		}
		collect(cells, 0)
		if len(page.Dramas) > 0 || !more {
			return page, ctx.Err()
		}
		offset, session = next, nextSession
	}
	return hongguoRecommendationPage{}, errors.New("本轮官方推荐暂无新剧集，可下拉刷新重试")
}
