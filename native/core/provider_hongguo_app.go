package core

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"
)

const hongguoAppBaseURL = "https://api5-normal-sinfonlineb.fqnovel.com"

const hongguoAppUserAgent = "com.phoenix.read/73532 (Linux; U; Android 16; zh_CN; 25053RT47C; Build/BP2A.250605.031.A3; Cronet/TTNetVersion:04657795 2026-01-23 QuicVersion:c67e9834 2025-09-08)"

type hongguoCatalogCursor struct {
	Offset        int       `json:"offset"`
	SessionID     string    `json:"sessionId,omitempty"`
	LastID        string    `json:"lastId,omitempty"`
	PageSignature string    `json:"pageSignature,omitempty"`
	Initialized   bool      `json:"initialized"`
	Exhausted     bool      `json:"exhausted"`
	UpdatedAt     time.Time `json:"updatedAt"`
}

type hongguoCatalogState struct {
	Version   int                             `json:"version"`
	DeviceID  string                          `json:"deviceId"`
	InstallID string                          `json:"installId"`
	Feeds     map[string]hongguoCatalogCursor `json:"feeds"`
}

type hongguoAppClient struct {
	mu             sync.Mutex
	catalogMu      sync.Mutex
	baseURL        string
	state          hongguoCatalogState
	details        map[string]hongguoDetailEntry
	pending        map[string]*hongguoDetailCall
	searches       map[string]hongguoSearchEntry
	searchPending  map[string]*hongguoSearchCall
	suggestions    map[string]hongguoSuggestionEntry
	suggestPending map[string]*hongguoSuggestionCall
	danmaku        map[string]hongguoDanmakuCacheEntry
	danmakuPending map[string]*hongguoDanmakuCall
}

func (downloader *Downloader) hongguoClient() *hongguoAppClient {
	downloader.hongguoOnce.Do(func() {
		downloader.hongguo = &hongguoAppClient{
			baseURL: hongguoAppBaseURL,
			state:   hongguoCatalogState{Version: 1, DeviceID: newHongguoDeviceID(), InstallID: newHongguoDeviceID(), Feeds: map[string]hongguoCatalogCursor{}},
			details: map[string]hongguoDetailEntry{}, pending: map[string]*hongguoDetailCall{},
			searches: map[string]hongguoSearchEntry{}, searchPending: map[string]*hongguoSearchCall{},
			suggestions: map[string]hongguoSuggestionEntry{}, suggestPending: map[string]*hongguoSuggestionCall{},
		}
	})
	return downloader.hongguo
}

func cloneHongguoCatalogState(state *hongguoCatalogState) *hongguoCatalogState {
	if state == nil {
		return nil
	}
	cloned := *state
	cloned.Feeds = make(map[string]hongguoCatalogCursor, len(state.Feeds))
	for name, cursor := range state.Feeds {
		cloned.Feeds[name] = cursor
	}
	return &cloned
}

func (downloader *Downloader) restoreHongguoCatalog(state *hongguoCatalogState) {
	if state == nil || state.Version != 1 || !hongguoNumericID.MatchString(state.DeviceID) || !hongguoNumericID.MatchString(state.InstallID) {
		return
	}
	cloned := cloneHongguoCatalogState(state)
	for name, cursor := range cloned.Feeds {
		known := false
		for _, genre := range hongguoAppGenres {
			known = known || name == genre.key || name == "category:"+genre.key
		}
		if !known || !cursor.Initialized || cursor.Offset < 0 || cursor.Offset > 1_000_000 || len(cursor.SessionID) > 4096 || len(cursor.LastID) > 256 || len(cursor.PageSignature) > 64 {
			delete(cloned.Feeds, name)
		}
	}
	client := downloader.hongguoClient()
	client.catalogMu.Lock()
	defer client.catalogMu.Unlock()
	client.mu.Lock()
	defer client.mu.Unlock()
	if len(client.state.Feeds) == 0 {
		client.state = *cloned
	}
}

func (downloader *Downloader) hongguoCatalogSnapshot() *hongguoCatalogState {
	client := downloader.hongguoClient()
	client.mu.Lock()
	defer client.mu.Unlock()
	return cloneHongguoCatalogState(&client.state)
}

func hongguoCatalogInitialized(state *hongguoCatalogState) bool {
	if state != nil && state.Version == 1 {
		for _, cursor := range state.Feeds {
			if cursor.Initialized {
				return true
			}
		}
	}
	return false
}

func hongguoCatalogHasMore(state *hongguoCatalogState) bool {
	for _, genre := range hongguoAppGenres {
		if state == nil || !state.Feeds[genre.key].Exhausted {
			return true
		}
	}
	return false
}

func (downloader *Downloader) hongguoAppRequest(ctx context.Context, method, path string, extra url.Values, payload any) (map[string]any, error) {
	client := downloader.hongguoClient()
	client.mu.Lock()
	base, deviceID, installID := client.baseURL, client.state.DeviceID, client.state.InstallID
	client.mu.Unlock()
	mediaRequest, _ := ctx.Value(hongguoMediaRequestKey{}).(bool)
	session, authenticated := ctx.Value(hongguoPlaybackSessionKey{}).(hgAccountSession)
	authenticated = mediaRequest && authenticated && hgHasCredentials(session) && hgValidID(session.DeviceID) && hgValidID(session.InstallID)
	if authenticated {
		deviceID, installID = session.DeviceID, session.InstallID
	}
	query := url.Values{
		"aid": {"8662"}, "app_name": {"novelread"}, "version_code": {"73532"}, "version_name": {"7.3.5.32"},
		"manifest_version_code": {"73532"}, "update_version_code": {"73532"}, "channel": {"update_64"},
		"device_platform": {"android"}, "os": {"android"}, "ssmix": {"a"}, "device_type": {"25053RT47C"},
		"device_brand": {"Redmi"}, "language": {"zh"}, "os_api": {"36"}, "os_version": {"16"},
		"resolution": {"1280*2772"}, "dpi": {"520"}, "ac": {"wifi"}, "device_id": {deviceID}, "iid": {installID},
	}
	if mediaRequest {
		for key, value := range map[string]string{"host_abi": "arm64-v8a", "dragon_device_type": "phone", "pv_player": "73532", "compliance_status": "0", "need_personal_recommend": "1", "player_so_load": "1", "is_android_pad_screen": "0"} {
			query.Set(key, value)
		}
		if authenticated {
			query.Set("cdid", session.Device.CDID)
			query.Set("openudid", session.Device.OpenUDID)
		}
	}
	for key, values := range extra {
		query[key] = append([]string(nil), values...)
	}
	var body []byte
	var err error
	if payload != nil {
		body, err = json.Marshal(payload)
		if err != nil {
			return nil, err
		}
	}
	attempts := downloader.cfg.Retries
	if attempts < 1 {
		attempts = 1
	}
	if attempts > 3 {
		attempts = 3
	}
	if mediaRequest && attempts < 2 {
		attempts = 2
	}
	var lastErr error
	for attempt := 0; attempt < attempts; attempt++ {
		if attempt > 0 {
			delay := time.Duration(attempt) * time.Second
			if mediaRequest {
				delay = 150 * time.Millisecond
			}
			select {
			case <-time.After(delay):
			case <-ctx.Done():
				return nil, ctx.Err()
			}
		}
		request, err := http.NewRequestWithContext(ctx, method, strings.TrimRight(base, "/")+path, bytes.NewReader(body))
		if err != nil {
			return nil, err
		}
		request.Header.Set("User-Agent", hongguoAppUserAgent)
		request.Header.Set("Accept", "application/json")
		request.Header.Set("X-XS-From-Web", "0")
		request.Header.Set("Sdk-Version", "2")
		transport := downloader.client
		if mediaRequest {
			scoped := *downloader.client
			scoped.Jar = nil
			scoped.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
			transport = &scoped
			request.Header.Set("X-SS-DP", "8662")
			request.Header.Set("X-Tt-Store-Region", "cn")
			request.Header.Set("X-Tt-Store-Region-Src", "did")
			request.Header.Set("X-Tt-Request-Tag", "t=0;n=0")
			request.Header.Set("Passport-Sdk-Version", "50561")
			if authenticated {
				for name, value := range session.Cookies {
					request.AddCookie(&http.Cookie{Name: name, Value: value})
				}
				if region := session.Cookies["store-region"]; region != "" {
					request.Header.Set("X-Tt-Store-Region", region)
				}
				if session.Token != "" {
					request.Header.Set("X-Tt-Token", session.Token)
				}
			}
		}
		comment, _ := ctx.Value(hongguoCommentKey{}).(bool)
		var commentNonce hongguoCommentNonce
		var playerNonce hongguoPlayerNonce
		if comment {
			commentNonce, err = newHongguoCommentNonce()
			if err != nil {
				return nil, errors.New("无法准备红果文字请求")
			}
			request.Header.Set("Comment-Source", "601")
			request.Header.Set("Server-Channel", "1000")
		} else {
			playerNonce, err = newHongguoPlayerNonce()
			if err != nil {
				return nil, errors.New("无法准备红果请求签名随机数")
			}
		}
		if payload != nil {
			request.Header.Set("Content-Type", "application/json; charset=utf-8")
		}
		finish := startPlaybackStage(ctx, fmt.Sprintf("app_http_attempt_%d", attempt+1))
		response, err := downloader.doPreparedCatalogRequestWithClient(request, 20*time.Second, func(prepared *http.Request) error {
			now := time.Now()
			if mediaRequest {
				query.Set("ts", strconv.FormatInt(now.Unix(), 10))
			}
			query.Set("_rticket", strconv.FormatInt(now.UnixMilli(), 10))
			prepared.URL.RawQuery = query.Encode()
			if comment {
				signHongguoCommentRequest(prepared, commentNonce, now)
			} else if mediaRequest && attempt == 0 {
				raw, headers, err := hgAuthSign(query, body, now.UnixMilli(), deviceID)
				if err != nil {
					return err
				}
				prepared.URL.RawQuery = raw
				for key, values := range headers {
					prepared.Header[key] = values
				}
				stamp := uint32(now.Unix())
				prepared.Header.Set("X-Ladon", base64.StdEncoding.EncodeToString(binary.BigEndian.AppendUint32(nil, stamp)))
				prepared.Header.Set("X-Argus", base64.StdEncoding.EncodeToString(binary.LittleEndian.AppendUint32(nil, stamp)))
			} else {
				signHongguoPlayerRequest(prepared, body, now, installID, playerNonce)
			}
			return nil
		}, transport)
		finish(err)
		if err != nil {
			lastErr = err
			var backoff *requestBackoff
			if errors.As(err, &backoff) || ctx.Err() != nil {
				return nil, err
			}
			continue
		}
		content, readErr := io.ReadAll(io.LimitReader(response.Body, providerMaxBodyBytes+1))
		response.Body.Close()
		if readErr != nil {
			lastErr = readErr
			continue
		}
		if response.StatusCode != http.StatusOK {
			lastErr = fmt.Errorf("红果 App 接口 HTTP %d", response.StatusCode)
			if response.StatusCode >= 400 && response.StatusCode < 500 {
				return nil, lastErr
			}
			continue
		}
		if len(bytes.TrimSpace(content)) == 0 {
			lastErr = fmt.Errorf("红果 App 接口 %s 返回 HTTP 200 空响应，可能触发服务端访问限制", path)
			continue
		}
		if len(content) > providerMaxBodyBytes {
			return nil, errors.New("红果 App 接口响应超过大小限制")
		}
		var result map[string]any
		decoder := json.NewDecoder(bytes.NewReader(content))
		decoder.UseNumber()
		if err := decoder.Decode(&result); err != nil || result == nil {
			return nil, errors.New("红果 App 接口返回格式异常")
		}
		code := firstNonEmpty(mapString(result, "code", "Code", "status_code"), mapString(nestedMap(result, "BaseResp"), "StatusCode"))
		if code != "" && code != "0" {
			// 服务端 message 往往携带被拒原因（签名失效 / 风控 / 频控），必须透出。
			message := firstNonEmpty(mapString(result, "message", "msg"), mapString(nestedMap(result, "BaseResp"), "StatusMessage"), mapString(nestedMap(result, "data"), "message"))
			if message != "" {
				return nil, fmt.Errorf("红果 App 接口暂不可用（%s）：%s", truncate(code, 20), truncate(message, 120))
			}
			return nil, fmt.Errorf("红果 App 接口暂不可用（%s）", truncate(code, 20))
		}
		return result, nil
	}
	return nil, lastErr
}
