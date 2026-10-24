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

	"golang.org/x/text/unicode/norm"
)

const hongguoRelatedSeasonsPath = "/reading/bookapi/plan/v"

var hongguoOfficialSeasonTag = regexp.MustCompile(`^第\s*([0-9零〇一二两兩三四五六七八九十百]+)\s*季$`)

func hongguoOfficialSeasonNumber(label string) int {
	label = norm.NFKC.String(strings.TrimSpace(label))
	tag := hongguoOfficialSeasonTag.FindStringSubmatch(label)
	if tag == nil {
		return 0
	}
	if number, err := strconv.Atoi(tag[1]); err == nil {
		if number > 0 && number < 1000 {
			return number
		}
		return 0
	}
	_, number, _, _ := hongguoSearchSeason("官方" + label)
	return number
}

func hongguoRelatedSeasonRows(cell map[string]any) ([]any, error) {
	rows, direct := cell["video_data"].([]any)
	if len(rows) > 0 {
		return rows, nil
	}
	children, nested := cell["cell_data"].([]any)
	if !direct && !nested {
		return nil, errors.New("红果相关作品缺少剧集数据")
	}
	for _, child := range children {
		videos, ok := nestedMap(child)["video_data"].([]any)
		if ok {
			rows = append(rows, videos...)
		}
	}
	return rows, nil
}

type hongguoOfficialSeason struct {
	Drama       nativeDrama `json:"drama"`
	Number      int         `json:"number"`
	Next        bool        `json:"next"`
	Playable    bool        `json:"playable"`
	Reservable  bool        `json:"reservable"`
	PublishText string      `json:"publishText"`
	Label       string      `json:"label"`
}

type hongguoOfficialSeasons struct {
	CurrentSeason int                     `json:"currentSeason"`
	Warning       string                  `json:"warning,omitempty"`
	Seasons       []hongguoOfficialSeason `json:"seasons"`
	RelatedWorks  []hongguoOfficialSeason `json:"relatedWorks"`
}

func hongguoRelatedSeasonsQuery(seriesID string) url.Values {
	return url.Values{"book_id": {seriesID}, "bookstore_tab": {"0"}, "bookstore_tab_type": {"0"}, "current_chapter_num": {"0"}, "from": {"detail_page_more_related"}, "is_horizontal_screen": {"false"}, "limit": {"0"}, "need_personal_recommend": {"1"}, "offset": {"0"}, "post_id": {"0"}, "scene": {"10"}, "total_chapter_num": {"0"}}
}

func hongguoOfficialDetailPayload(seriesID string) map[string]any {
	return map[string]any{"series_id": seriesID, "biz_param": map[string]any{"caller_scene": "single_col", "detail_page_version": 1, "disable_digg_stat": false, "disable_video_relate_book": false, "from_video_id": "", "need_all_video_definition": false, "need_mp4_align": false, "screen_width_px": "1078", "source": 4, "use_os_player": false, "use_server_dns": false, "video_id_type": 1}}
}

func parseHongguoOfficialSeasons(result map[string]any, current nativeDrama, currentSeason int) (hongguoOfficialSeasons, error) {
	response := hongguoOfficialSeasons{CurrentSeason: currentSeason, Seasons: []hongguoOfficialSeason{}, RelatedWorks: []hongguoOfficialSeason{}}
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
		rows, err := hongguoRelatedSeasonRows(cell)
		if err != nil {
			return response, err
		}
		for _, item := range rows {
			row := nestedMap(item)
			label := strings.TrimSpace(mapString(nestedMap(row, "tag_info"), "text"))
			number := hongguoOfficialSeasonNumber(label)
			id := mapString(row, "series_id")
			if !hongguoNumericID.MatchString(id) || seen[id] {
				continue
			}
			seen[id] = true
			episodes, episodeErr := strconv.Atoi(mapString(row, "episode_cnt"))
			reservable := episodeErr == nil && episodes == 0
			playable := episodes > 0 && !hgBool(row["disable_play"])
			drama := nativeDrama{ID: providerDramaID(sourceHongguo, id), Source: sourceHongguo, SourceID: id, Title: mapString(row, "title"), Description: mapString(row, "video_desc"), Cover: mapString(row, "cover"), Episodes: max(0, episodes)}
			if drama.Title == "" {
				continue
			}
			if number > 0 && drama.ID == current.ID {
				response.CurrentSeason = number
			}
			publish := hongguoPublishText(time.Now(), row)
			work := hongguoOfficialSeason{Drama: drama, Number: number, Playable: playable, Reservable: reservable, PublishText: publish, Label: label}
			response.RelatedWorks = append(response.RelatedWorks, work)
			if number > 0 {
				response.Seasons = append(response.Seasons, work)
			}
		}
	}
	currentIncluded := false
	for _, season := range response.Seasons {
		if season.Drama.ID == current.ID {
			currentIncluded = true
			break
		}
	}
	if response.CurrentSeason > 0 && !currentIncluded {
		response.Seasons = append(response.Seasons, hongguoOfficialSeason{Drama: current, Number: response.CurrentSeason, Playable: current.Episodes > 0})
	}
	sort.SliceStable(response.Seasons, func(i, j int) bool { return response.Seasons[i].Number < response.Seasons[j].Number })
	for i := range response.Seasons {
		season := &response.Seasons[i]
		if response.CurrentSeason > 0 && season.Number > response.CurrentSeason && season.Playable {
			season.Next = true
			return response, nil
		}
	}
	for _, season := range response.Seasons {
		if season.Number > response.CurrentSeason && season.Drama.Episodes > 0 {
			return response, nil
		}
	}
	for i := range response.Seasons {
		season := &response.Seasons[i]
		if response.CurrentSeason > 0 && season.Number > response.CurrentSeason && !season.Playable && season.Reservable {
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
	a.mu.Lock()
	session, generation := hgCloneSession(a.disk.Session), a.generation
	a.mu.Unlock()
	client := hgNewAccountHTTP(a.downloader, session)
	if err := client.register(ctx); err != nil {
		return hongguoOfficialSeasons{}, err
	}
	cache := a.downloader.hongguoClient()
	cache.mu.Lock()
	entry, found := cache.details[seriesID]
	cache.mu.Unlock()
	var detailErr error
	if !found || !time.Now().Before(entry.ExpiresAt) {
		detail, requestErr := client.json(ctx, "/novel/player/video_detail/v1/", http.MethodPost, nil, hongguoOfficialDetailPayload(seriesID), false)
		detailErr = requestErr
		if requestErr == nil {
			if fresh, parseErr := parseHongguoAppDetail(detail, seriesID); parseErr == nil {
				entry = fresh
			} else {
				detailErr = parseErr
				if fresh.CurrentSeason > 0 {
					entry.CurrentSeason = fresh.CurrentSeason
				}
				if entry.Drama.ID == "" && fresh.Drama.ID != "" {
					entry.Drama = fresh.Drama
				}
			}
		}
	}
	if ctx.Err() != nil {
		return hongguoOfficialSeasons{}, ctx.Err()
	}
	current := nativeNormalize(entry.Drama)
	current.ID, current.Source, current.SourceID = providerDramaID(sourceHongguo, seriesID), sourceHongguo, seriesID
	if current.Title == "" {
		current.Title = "当前作品"
	}
	var seasons hongguoOfficialSeasons
	var lastErr error
	loaded := false
	for attempt := 0; attempt < 4; attempt++ {
		if attempt > 0 {
			timer := time.NewTimer(time.Duration(100+300*attempt) * time.Millisecond)
			select {
			case <-ctx.Done():
				timer.Stop()
				return hongguoOfficialSeasons{}, ctx.Err()
			case <-timer.C:
			}
		}
		result, requestErr := client.json(ctx, hongguoRelatedSeasonsPath, http.MethodGet, hongguoRelatedSeasonsQuery(seriesID), nil, false)
		if requestErr != nil {
			lastErr = requestErr
			continue
		}
		parsed, parseErr := parseHongguoOfficialSeasons(result, current, entry.CurrentSeason)
		if parseErr != nil {
			lastErr = parseErr
			continue
		}
		seasons, loaded, lastErr = parsed, true, nil
		if len(seasons.RelatedWorks) > 0 {
			break
		}
	}
	if !loaded {
		return hongguoOfficialSeasons{}, lastErr
	}
	if seasons.CurrentSeason == 0 && detailErr != nil {
		seasons.Warning = "相关作品已读取，但当前季号暂未确认，请刷新重试"
	} else if lastErr != nil {
		seasons.Warning = "相关作品补查暂未完成，请刷新重试"
	}
	a.mu.Lock()
	changed := a.generation != generation
	a.mu.Unlock()
	if ctx.Err() != nil || changed {
		return hongguoOfficialSeasons{}, errors.New("相关作品查询已取消")
	}
	if len(entry.Chapters) == 0 || detailErr != nil {
		return seasons, nil
	}
	cache.mu.Lock()
	if len(cache.details) >= 128 {
		cache.details = map[string]hongguoDetailEntry{}
	}
	entry.Seasons = seasons.Seasons
	entry.CurrentSeason = seasons.CurrentSeason
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
