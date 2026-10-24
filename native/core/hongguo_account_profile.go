package core

import (
	"context"
	"errors"
	"net/http"
	"net/url"
	"strings"
)

func hgProfileData(payload map[string]any) map[string]any {
	data := nestedMap(payload, "data")
	if inner, ok := data["user_info"].(map[string]any); ok {
		return inner
	}
	return data
}

func hgMergeProfile(data map[string]any, previous hgAccountProfile) hgAccountProfile {
	if name := strings.TrimSpace(mapString(data, "name", "user_name", "username", "nick_name", "screen_name")); name != "" {
		previous.Name = name
	}
	if avatar := strings.TrimSpace(mapString(data, "avatar_url", "avatar")); avatar != "" {
		parsed, err := url.Parse(avatar)
		if err == nil && parsed.Host != "" && parsed.User == nil && (parsed.Scheme == "https" || parsed.Scheme == "http") {
			previous.AvatarURL = avatar
		}
	}
	if id := mapString(data, "biz_user_id"); hgValidID(id) {
		previous.PublicID = id
	}
	return previous
}

func (c *hgAccountHTTP) accountProfile(ctx context.Context, previous hgAccountProfile) (hgAccountProfile, error) {
	payload, err := c.json(ctx, "/reading/user/info/v1/", http.MethodGet, nil, nil, false)
	if err != nil {
		return previous, err
	}
	data := hgProfileData(payload)
	if len(data) == 0 {
		return previous, errors.New("红果用户资料响应为空")
	}
	for _, key := range []string{"req_id", "user_id_str", "user_id", "uid"} {
		id := mapString(data, key)
		if hgValidID(id) && id != previous.UID {
			return previous, errors.New("红果用户资料身份不匹配，已保留原账号")
		}
	}
	return hgMergeProfile(data, previous), nil
}

func (a *hgOfficialAccount) refreshProfile(ctx context.Context, uid string) (err error) {
	if err = a.requireOwner(uid); err != nil {
		return err
	}
	ctx, c, g, finish, err := a.begin(ctx)
	if err != nil {
		return err
	}
	defer finish()
	defer func() {
		a.mu.Lock()
		defer a.mu.Unlock()
		if a.generation == g {
			a.profileError = ""
			if err != nil {
				a.profileError = err.Error()
			}
		}
	}()
	a.mu.Lock()
	if a.disk.Profile == nil || a.disk.Profile.UID != uid {
		a.mu.Unlock()
		return errors.New("红果账号已变更")
	}
	previous := *a.disk.Profile
	a.mu.Unlock()
	updated, err := c.accountProfile(ctx, previous)
	if err != nil {
		return err
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	if ctx.Err() != nil || a.generation != g || a.disk.Profile == nil || a.disk.Profile.UID != uid {
		return errors.New("红果用户资料刷新已取消")
	}
	disk := a.disk
	disk.Profile = &updated
	disk.Session = hgCloneSession(c.session)
	if err = a.saveSession(disk); err != nil {
		return errors.New("红果用户资料尚未保存")
	}
	a.disk = disk
	return nil
}
