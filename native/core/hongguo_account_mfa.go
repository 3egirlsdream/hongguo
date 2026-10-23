package core

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

type hgAccountMFA struct {
	EncryptUID  string
	Number      string
	Content     string
	Scene       string
	Reason      string
	Copywriting string
	Diversion   string
	LogID       string
	BizParams   map[string]string
}

func hgParseAccountMFA(data map[string]any) *hgAccountMFA {
	biz := nestedMap(data, "biz_params")
	if raw, ok := data["biz_params"].(string); ok {
		biz, _ = hgDecodeObject([]byte(raw))
	}
	params := map[string]string{}
	for key, value := range biz {
		if s, ok := value.(string); ok {
			params[key] = s
		} else if s := mapString(biz, key); s != "" {
			params[key] = s
		}
	}
	params["sms_code_key"] = firstNonEmpty(params["sms_code_key"], mapString(data, "sms_code_key"))
	params["passport_mfa_retry_tag"] = firstNonEmpty(params["passport_mfa_retry_tag"], mapString(data, "passport_mfa_retry_tag"), "1")
	event, common := nestedMap(data, "event_params"), nestedMap(data, "common_params")
	mfa := &hgAccountMFA{
		EncryptUID: mapString(data, "encrypt_uid"), BizParams: params,
		Scene:       firstNonEmpty(mapString(event, "verify_scene"), mapString(data, "passport_scene"), "sms_login"),
		Reason:      firstNonEmpty(mapString(event, "verify_reason"), "ato"),
		Copywriting: firstNonEmpty(mapString(common, "copywriting_key"), "sms_login"),
		Diversion:   firstNonEmpty(mapString(common, "ies_safety_diversion_tag"), "mfa"),
		LogID:       mapString(event, "log_id"),
	}
	for _, value := range anyList(data["verify_ways"]) {
		way := nestedMap(value)
		if mapString(way, "channel_mobile") != "" && mapString(way, "sms_content") != "" {
			mfa.Number, mfa.Content = mapString(way, "channel_mobile"), mapString(way, "sms_content")
			break
		}
	}
	if mfa.EncryptUID == "" || params["sms_code_key"] == "" || mfa.Number == "" || mfa.Content == "" {
		return nil
	}
	return mfa
}

func (c *hgAccountHTTP) verifyMFA(ctx context.Context, mfa *hgAccountMFA) (map[string]any, error) {
	biz, err := json.Marshal(mfa.BizParams)
	if err != nil {
		return nil, err
	}
	form := url.Values{
		"encrypt_uid": {mfa.EncryptUID}, "verify_ticket": {""},
		"verify_scene": {mfa.Scene}, "verify_reason": {mfa.Reason},
		"copywriting_key": {mfa.Copywriting}, "ies_safety_diversion_tag": {mfa.Diversion},
		"new_verify_flow": {""}, "new_authn_sdk_version": {"1.1.31"},
		"new_authn_sdk_verify_reason": {mfa.Reason}, "new_authn_sdk_verify_scene": {mfa.Scene},
		"request_tag_from": {"h5"}, "biz_params": {string(biz)}, "new_authn_sdk_log_id": {mfa.LogID},
	}
	return c.request(ctx, "/passport/upsms/verify/", http.MethodPost, nil, []byte(form.Encode()), "application/x-www-form-urlencoded; charset=UTF-8", false)
}

func hgPassportErrorCode(payload map[string]any) string {
	for _, row := range []map[string]any{nestedMap(payload, "data"), payload} {
		for _, key := range []string{"error_code", "code"} {
			if code := mapString(row, key); code != "" && code != "0" {
				return code
			}
		}
	}
	return ""
}

func hgPassportFailure(payload map[string]any, message string) error {
	if code, err := strconv.ParseUint(hgPassportErrorCode(payload), 10, 32); err == nil {
		return fmt.Errorf("%s（错误码 %d）", message, code)
	}
	return errors.New(message)
}

func hgUpSMSVerified(payload map[string]any) (bool, error) {
	code := hgPassportErrorCode(payload)
	if code == "1045" {
		return false, nil
	}
	if code != "" || mapString(payload, "message") == "error" {
		return false, hgPassportFailure(payload, "检查短信验证失败，请在当前页面重试")
	}
	data := nestedMap(payload, "data")
	if data == nil {
		return false, errors.New("短信验证响应不完整，请在当前页面重试")
	}
	if _, exists := data["registered"]; exists {
		switch mapString(data, "registered") {
		case "true", "1":
			return true, nil
		case "false", "0":
			return false, nil
		default:
			return false, errors.New("短信验证状态格式无效，请在当前页面重试")
		}
	}
	return hgPassportSuccess(payload) && mapString(data, "ticket", "verify_ticket") != "", nil
}

func hgVerificationExpired(payload map[string]any) bool {
	for _, row := range []map[string]any{payload, nestedMap(payload, "data")} {
		description := mapString(row, "description", "message")
		for _, phrase := range []string{"验证已过期", "验证过期", "验证已失效", "长时间未操作", "验证码已过期", "验证码过期", "验证码已失效"} {
			if strings.Contains(description, phrase) {
				return true
			}
		}
	}
	return false
}

func (a *hgOfficialAccount) persistLoginAttempt(ctx context.Context, c *hgAccountHTTP, g uint64, attempt hgLoginAttempt) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	if ctx.Err() != nil || g != a.generation || !time.Now().Before(attempt.Expires) {
		return errors.New("本次登录已取消或已超时")
	}
	disk := a.disk
	disk.Session = hgCloneSession(c.session)
	if err := a.saveSession(disk); err != nil {
		return err
	}
	a.disk, a.attempt = disk, &attempt
	return nil
}

func (a *hgOfficialAccount) rejectExpiredLogin(ctx context.Context, g uint64, payload map[string]any) error {
	err := hgPassportFailure(payload, "本次短信验证已过期，请在此重新获取验证码")
	a.mu.Lock()
	defer a.mu.Unlock()
	if ctx.Err() == nil && g == a.generation {
		a.attempt = nil
		a.loginError = err.Error()
		a.generation++
	}
	return err
}
