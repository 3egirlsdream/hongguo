package core

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

func (c *hgAccountHTTP) registerPlayback(ctx context.Context, downloader *Downloader) error {
	if c.session.Registered && hgValidID(c.session.DeviceID) && hgValidID(c.session.InstallID) {
		return nil
	}
	d := c.session.Device
	header := map[string]any{
		"display_name": "红果免费短剧", "aid": 8662, "app_version": "7.3.5.32", "version_code": 73532,
		"manifest_version_code": 73532, "update_version_code": 73532, "channel": "update_64", "package": "com.phoenix.read",
		"app_language": "zh", "os": "Android", "os_version": "16", "os_api": 36, "device_model": "25053RT47C",
		"device_brand": "Redmi", "device_manufacturer": "Xiaomi", "cpu_abi": "arm64-v8a", "density_dpi": 520,
		"display_density": "xxhdpi", "resolution": "2772x1280", "language": "zh", "timezone": 8, "access": "wifi",
		"openudid": d.OpenUDID, "clientudid": d.ClientUDID, "cdid": d.CDID,
		"region": "CN", "tz_name": "Asia/Shanghai", "tz_offset": 28800, "sim_region": "cn", "device_platform": "android",
		"not_request_sender": 0, "is_system_app": 0, "sdk_flavor": "china", "rom": "OS2.0", "rom_version": "BP2A.250605.031.A3",
	}
	body, err := json.Marshal(map[string]any{"magic_tag": "ss_app_log", "header": header, "_gen_time": time.Now().UnixMilli()})
	if err != nil {
		return err
	}
	query := c.playbackQuery()
	query.Del("device_id")
	query.Del("iid")
	query.Set("req_id", d.CDID)
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://log.snssdk.com/service/2/device_register/", bytes.NewReader(body))
	if err != nil {
		return err
	}
	request.Header.Set("User-Agent", hongguoAppUserAgent)
	request.Header.Set("Accept", "application/json")
	request.Header.Set("Content-Type", "application/json; charset=utf-8")
	response, err := downloader.doPreparedCatalogRequestWithClient(request, 5*time.Second, func(prepared *http.Request) error {
		query.Set("_rticket", strconv.FormatInt(time.Now().UnixMilli(), 10))
		prepared.URL.RawQuery = query.Encode()
		return nil
	}, c.http)
	if err != nil {
		return err
	}
	raw, err := hgReadResponse(response)
	if err != nil {
		return err
	}
	result, err := hgDecodeObject(raw)
	if err != nil {
		return err
	}
	did, iid := mapString(result, "device_id_str", "device_id"), mapString(result, "install_id_str", "install_id")
	if !hgValidID(did) || !hgValidID(iid) {
		return errors.New("红果播放设备注册未返回有效身份")
	}
	c.session.DeviceID, c.session.InstallID, c.session.Registered = did, iid, true
	return nil
}

func (c *hgAccountHTTP) playbackQuery() url.Values {
	query := c.query()
	query.Del("cdid")
	query.Del("openudid")
	return query
}

func (c *hgAccountHTTP) playbackModel(ctx context.Context, downloader *Downloader, videoID string) (map[string]any, error) {
	body, err := json.Marshal(map[string]any{
		"video_id": videoID, "content_type": 1,
		"biz_param": map[string]any{"need_all_video_definition": true, "video_platform": 3},
	})
	if err != nil {
		return nil, err
	}
	client := downloader.hongguoClient()
	client.mu.Lock()
	base := client.baseURL
	client.mu.Unlock()
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimRight(base, "/")+"/novel/player/video_model/v1/", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	request.Header.Set("User-Agent", hongguoAppUserAgent)
	request.Header.Set("Accept", "application/json")
	request.Header.Set("Content-Type", "application/json; charset=utf-8")
	query := c.playbackQuery()
	nonce, err := newHongguoPlayerNonce()
	if err != nil {
		return nil, err
	}
	response, err := downloader.doPreparedCatalogRequestWithClient(request, 5*time.Second, func(prepared *http.Request) error {
		now := time.Now()
		query.Set("_rticket", strconv.FormatInt(now.UnixMilli(), 10))
		prepared.URL.RawQuery = query.Encode()
		signHongguoPlayerRequest(prepared, body, now, c.session.DeviceID, nonce)
		return nil
	}, c.http)
	if err != nil {
		return nil, err
	}
	raw, err := hgReadResponse(response)
	if err != nil {
		if errors.Is(err, errHGEmptyResponse) && response.Header.Get("Retry-After") != "" {
			return nil, errors.New("红果播放接口返回空响应，上游要求稍后重试")
		}
		return nil, err
	}
	result, err := hgDecodeObject(raw)
	if err != nil {
		return nil, err
	}
	if err := hgAPIError(result); err != nil {
		return nil, err
	}
	return result, nil
}
