package core

import (
	"context"
	"errors"
	"net/http"
	"net/url"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

const hongguoRelatedSeasonsPath = "/reading/bookapi/plan/v"

var hongguoOfficialSeasonTag = regexp.MustCompile(`^第([1-9][0-9]{0,2})季$`)

type hongguoOfficialSeason struct {
	Drama       nativeDrama `json:"drama"`
	Number      int         `json:"number"`
	Next        bool        `json:"next"`
	Playable    bool        `json:"playable"`
	Reservable  bool        `json:"reservable"`
	PublishText string      `json:"publishText"`
}

type hongguoOfficialSeasons struct {
	CurrentSeason int                     `json:"currentSeason"`
	Seasons       []hongguoOfficialSeason `json:"seasons"`
}

func hongguoRelatedSeasonsQuery(seriesID string) url.Values {
	return url.Values{"book_id": {seriesID}, "bookstore_tab": {"0"}, "bookstore_tab_type": {"0"}, "current_chapter_num": {"0"}, "from": {"detail_page_more_related"}, "is_horizontal_screen": {"false"}, "limit": {"0"}, "need_personal_recommend": {"1"}, "offset": {"0"}, "post_id": {"0"}, "scene": {"10"}, "total_chapter_num": {"0"}}
}

func hongguoOfficialDetailPayload(seriesID string) map[string]any {
	return map[string]any{"series_id": seriesID, "biz_param": map[string]any{"caller_scene": "single_col", "detail_page_version": 1, "disable_digg_stat": false, "disable_video_relate_book": false, "from_video_id": "", "need_all_video_definition": false, "need_mp4_align": false, "screen_width_px": "1078", "source": 4, "use_os_player": false, "use_server_dns": false, "video_id_type": 1}}
}

func parseHongguoOfficialSeasons(result map[string]any, current nativeDrama, currentSeason int) (hongguoOfficialSeasons, error) {
	response := hongguoOfficialSeasons{CurrentSeason: currentSeason, Seasons: []hongguoOfficialSeason{}}
	if _, ok := result["code"]; !ok {
		return response, errors.New("红果相关作品未返回操作状态")
	}
	if err := hgAPIError(result); err != nil {
		return response, err
	}
	cells, ok := result["data"].([]any)
	if !ok {
		return response, errors.New("红果相关作品缺少列表")
	}
	seen := map[string]bool{}
	for _, item := range cells {
		cell := nestedMap(item)
		if mapString(cell, "cell_name") != "相关作品" {
			continue
		}
		rows, ok := cell["video_data"].([]any)
		if !ok {
			return response, errors.New("红果相关作品缺少剧集数据")
		}
		for _, item := range rows {
			row := nestedMap(item)
			tag := hongguoOfficialSeasonTag.FindStringSubmatch(strings.TrimSpace(mapString(nestedMap(row, "tag_info"), "text")))
			if tag == nil {
				continue
			}
			number, _ := strconv.Atoi(tag[1])
			id := mapString(row, "series_id")
			if !hongguoNumericID.MatchString(id) || seen[id] {
				continue
			}
			seen[id] = true
			episodes, _ := strconv.Atoi(mapString(row, "episode_cnt"))
			_, hasReservation := row["online_subscribed"]
			reservable := hasReservation && episodes == 0
			playable := episodes > 0 && !hgBool(row["disable_play"])
			drama := nativeDrama{ID: providerDramaID(sourceHongguo, id), Source: sourceHongguo, SourceID: id, Title: mapString(row, "title"), Description: mapString(row, "video_desc"), Cover: mapString(row, "cover"), Episodes: max(0, episodes)}
			if drama.Title == "" {
				continue
			}
			if drama.ID == current.ID {
				response.CurrentSeason = number
			}
			publish := firstNonEmpty(mapString(row, "expected_rec_text", "publish_text"), hongguoOnlineDate(row, time.Now()))
			response.Seasons = append(response.Seasons, hongguoOfficialSeason{Drama: drama, Number: number, Playable: playable, Reservable: reservable, PublishText: publish})
		}
	}
	if response.CurrentSeason > 0 && !seen[current.SourceID] {
		response.Seasons = append(response.Seasons, hongguoOfficialSeason{Drama: current, Number: response.CurrentSeason, Playable: current.Episodes > 0})
	}
	sort.SliceStable(response.Seasons, func(i, j int) bool { return response.Seasons[i].Number < response.Seasons[j].Number })
	for i := range response.Seasons {
		season := &response.Seasons[i]
		if response.CurrentSeason > 0 && season.Number > response.CurrentSeason && (season.Playable || season.Reservable) {
			season.Next = true
			break
		}
	}
	return response, nil
}

func (a *hgOfficialAccount) seasons(ctx context.Context, seriesID string) (hongguoOfficialSeasons, error) {
	if !hongguoNumericID.MatchString(seriesID) {
		return hongguoOfficialSeasons{}, errors.New("多季剧集身份无效")
	}
	ctx, client, generation, finish, err := a.begin(ctx)
	if err != nil {
		return hongguoOfficialSeasons{}, err
	}
	defer finish()
	if err = client.register(ctx); err != nil {
		return hongguoOfficialSeasons{}, err
	}
	if err = a.persistClient(ctx, client, generation); err != nil {
		return hongguoOfficialSeasons{}, err
	}
	cache := a.downloader.hongguoClient()
	cache.mu.Lock()
	entry, found := cache.details[seriesID]
	cache.mu.Unlock()
	if !found || !time.Now().Before(entry.ExpiresAt) {
		detail, requestErr := client.json(ctx, "/novel/player/video_detail/v1/", http.MethodPost, nil, hongguoOfficialDetailPayload(seriesID), false)
		if requestErr != nil {
			return hongguoOfficialSeasons{}, requestErr
		}
		entry, err = parseHongguoAppDetail(detail, seriesID)
		if err != nil {
			return hongguoOfficialSeasons{}, err
		}
	}
	current := nativeNormalize(entry.Drama)
	current.SourceID = seriesID
	result, err := client.json(ctx, hongguoRelatedSeasonsPath, http.MethodGet, hongguoRelatedSeasonsQuery(seriesID), nil, false)
	if err != nil {
		return hongguoOfficialSeasons{}, err
	}
	seasons, err := parseHongguoOfficialSeasons(result, current, entry.CurrentSeason)
	if err != nil {
		return hongguoOfficialSeasons{}, err
	}
	if err = a.persistClient(ctx, client, generation); err != nil {
		return hongguoOfficialSeasons{}, err
	}
	cache.mu.Lock()
	if len(cache.details) >= 128 {
		cache.details = map[string]hongguoDetailEntry{}
	}
	entry.Seasons = seasons.Seasons
	entry.ExpiresAt = time.Now().Add(5 * time.Minute)
	cache.details[seriesID] = entry
	cache.mu.Unlock()
	return seasons, nil
}

func (a *hgOfficialAccount) playbackDetail(ctx context.Context, seriesID string) (hongguoDetailEntry, error) {
	if !hongguoNumericID.MatchString(seriesID) {
		return hongguoDetailEntry{}, errors.New("剧集身份无效")
	}
	cache := a.downloader.hongguoClient()
	cache.mu.Lock()
	cached, found := cache.details[seriesID]
	cache.mu.Unlock()
	if found && time.Now().Before(cached.ExpiresAt) {
		startPlaybackStage(ctx, "detail_cache_hit")(nil)
		return cached, nil
	}
	ctx, client, generation, finish, err := a.begin(ctx)
	if err != nil {
		return hongguoDetailEntry{}, err
	}
	defer finish()
	finishRegister := startPlaybackStage(ctx, "device_register")
	err = client.register(ctx)
	finishRegister(err)
	if err != nil {
		return hongguoDetailEntry{}, err
	}
	if err = a.persistClient(ctx, client, generation); err != nil {
		return hongguoDetailEntry{}, err
	}
	finishDetail := startPlaybackStage(ctx, "official_detail_api")
	result, err := client.json(ctx, "/novel/player/video_detail/v1/", http.MethodPost, nil, hongguoOfficialDetailPayload(seriesID), false)
	finishDetail(err)
	if err != nil {
		return hongguoDetailEntry{}, err
	}
	entry, err := parseHongguoAppDetail(result, seriesID)
	if err != nil {
		return hongguoDetailEntry{}, err
	}
	if err = a.persistClient(ctx, client, generation); err != nil {
		return hongguoDetailEntry{}, err
	}
	cache.mu.Lock()
	if len(cache.details) >= 128 {
		cache.details = map[string]hongguoDetailEntry{}
	}
	entry.ExpiresAt = time.Now().Add(5 * time.Minute)
	cache.details[seriesID] = entry
	cache.mu.Unlock()
	return entry, nil
}
