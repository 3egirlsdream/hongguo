package core

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

type hgAccountProfile struct {
	UID   string `json:"uid"`
	Name  string `json:"name"`
	Phone string `json:"phone"`
}
type hgAccountDisk struct {
	Version int               `json:"version"`
	Session hgAccountSession  `json:"session"`
	Profile *hgAccountProfile `json:"profile,omitempty"`
}
type hgOfficialWatch struct {
	Drama     nativeDrama `json:"drama"`
	Episode   int         `json:"episode"`
	VideoID   string      `json:"videoId"`
	Position  float64     `json:"position"`
	Duration  float64     `json:"duration"`
	UpdatedAt time.Time   `json:"updatedAt"`
}
type hgOfficialLibrary struct {
	Favorites []nativeDrama              `json:"favorites,omitempty"`
	UID       string                     `json:"uid"`
	History   map[string]hgOfficialWatch `json:"history"`
	Pending   map[string]hgOfficialWatch `json:"pending"`
	LastSync  time.Time                  `json:"lastSync"`
}
type hgLoginAttempt struct {
	Phone    string
	Code     string
	MFA      *hgAccountMFA
	Verified bool
	Expires  time.Time
}
type hgAccountInput struct {
	Refresh         bool            `json:"refresh"`
	Followed        bool            `json:"followed"`
	SubscribeOffset *int            `json:"subscribeOffset"`
	UID             string          `json:"uid"`
	Phone           string          `json:"phone"`
	Code            string          `json:"code"`
	ID              string          `json:"id"`
	Reserved        bool            `json:"reserved"`
	Mode            string          `json:"mode"`
	Offset          int             `json:"offset"`
	Cursor          string          `json:"cursor"`
	Watch           hgOfficialWatch `json:"watch"`
}
type hgOfficialAccount struct {
	mu         sync.Mutex
	operation  sync.Mutex
	dir        string
	downloader *Downloader
	disk       hgAccountDisk
	attempt    *hgLoginAttempt
	generation uint64
	cancel     context.CancelFunc
	retry      time.Time
	busy       bool
	loginError string
	syncError  string
	library    hgOfficialLibrary
}

var hgLocalProfileID = regexp.MustCompile(`^[a-zA-Z0-9_-]{1,64}$`)
var hgPhone = regexp.MustCompile(`^1[3-9][0-9]{9}$`)
var hgCode = regexp.MustCompile(`^[0-9]{4,8}$`)

func (engine *nativeEngine) officialAccount(profile string) (*hgOfficialAccount, error) {
	if !hgLocalProfileID.MatchString(profile) {
		return nil, errors.New("请先登录本地用户")
	}
	engine.accountMu.Lock()
	defer engine.accountMu.Unlock()
	if engine.accounts == nil {
		engine.accounts = map[string]*hgOfficialAccount{}
	}
	if a := engine.accounts[profile]; a != nil {
		return a, nil
	}
	a := &hgOfficialAccount{dir: filepath.Join(engine.directory, "hongguo-accounts", profile), downloader: engine.downloader, disk: hgAccountDisk{Version: 1}}
	b, e := os.ReadFile(filepath.Join(a.dir, "session.json"))
	if e == nil {
		if len(b) > 1<<20 || json.Unmarshal(b, &a.disk) != nil || a.disk.Version != 1 {
			return nil, errors.New("红果账号文件损坏，原文件已保留")
		}
		if a.disk.Profile != nil && (!hgValidID(a.disk.Profile.UID) || !hgHasCredentials(a.disk.Session)) {
			return nil, errors.New("红果账号凭证不完整，请重新登录")
		}
	} else if !errors.Is(e, os.ErrNotExist) {
		return nil, e
	}
	if a.disk.Session.Device.CDID == "" {
		identity, e := hgNewIdentity()
		if e != nil {
			return nil, e
		}
		a.disk.Session.Device = identity
		if e = a.saveSession(a.disk); e != nil {
			return nil, e
		}
	}
	if a.disk.Profile != nil {
		if e = a.loadLibrary(a.disk.Profile.UID); e != nil {
			return nil, e
		}
	}
	engine.accounts[profile] = a
	return a, nil
}
func hgHasCredentials(s hgAccountSession) bool {
	return s.Token != "" || s.Cookies["sessionid"] != "" || s.Cookies["sessionid_ss"] != ""
}
func (a *hgOfficialAccount) saveSession(d hgAccountDisk) error {
	b, e := json.Marshal(d)
	if e == nil {
		e = writeNativeCacheFile(filepath.Join(a.dir, "session.json"), b)
	}
	if e != nil {
		return errors.New("红果账号信息尚未保存，请检查存储空间")
	}
	return nil
}
func (a *hgOfficialAccount) libraryPath(uid string) string {
	return filepath.Join(a.dir, uid, "history.json")
}
func (a *hgOfficialAccount) loadLibrary(uid string) error {
	l := hgOfficialLibrary{UID: uid, History: map[string]hgOfficialWatch{}, Pending: map[string]hgOfficialWatch{}}
	b, e := os.ReadFile(a.libraryPath(uid))
	if e == nil {
		if len(b) > 32<<20 || json.Unmarshal(b, &l) != nil || l.UID != uid || l.History == nil || l.Pending == nil {
			return errors.New("红果账号历史文件无效，原文件已保留")
		}
	} else if !errors.Is(e, os.ErrNotExist) {
		return e
	}
	a.library = l
	return nil
}
func (a *hgOfficialAccount) saveLibrary(l hgOfficialLibrary) error {
	b, e := json.Marshal(l)
	if len(b) > 32<<20 {
		return errors.New("红果账号历史超过保存上限")
	}
	if e == nil {
		e = writeNativeCacheFile(a.libraryPath(l.UID), b)
	}
	return e
}
func hgCopyLibrary(l hgOfficialLibrary) hgOfficialLibrary {
	copy := l
	copy.Favorites = append([]nativeDrama(nil), l.Favorites...)
	copy.History = map[string]hgOfficialWatch{}
	copy.Pending = map[string]hgOfficialWatch{}
	for k, v := range l.History {
		copy.History[k] = v
	}
	for k, v := range l.Pending {
		copy.Pending[k] = v
	}
	return copy
}
func (a *hgOfficialAccount) status() map[string]any {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.attempt != nil && !time.Now().Before(a.attempt.Expires) {
		a.loginError = "本次登录已超时，请在此重新获取验证码"
		if a.attempt.MFA != nil {
			a.loginError = "本次短信验证已过期，请在此重新获取验证码"
		}
		a.generation++
		if a.cancel != nil {
			a.cancel()
		}
		a.attempt = nil
	}
	phase := "phone"
	if a.attempt != nil && time.Now().Before(a.attempt.Expires) {
		phase = "code"
		if a.attempt.MFA != nil {
			phase = "mfa"
		}
	}
	if a.disk.Profile != nil {
		phase = "loggedIn"
	}
	result := map[string]any{"loggedIn": a.disk.Profile != nil, "profile": a.disk.Profile, "phase": phase, "busy": a.busy, "retryAfter": max(0, int(math.Ceil(time.Until(a.retry).Seconds()))), "pending": len(a.library.Pending), "lastSync": a.library.LastSync, "syncError": a.syncError, "loginError": a.loginError}
	if phase == "mfa" {
		result["smsNumber"], result["smsContent"] = a.attempt.MFA.Number, a.attempt.MFA.Content
		result["expiresAt"] = a.attempt.Expires
		result["verificationState"] = "waiting"
		if a.attempt.Verified {
			result["verificationState"] = "verified"
		}
	}
	return result
}
func (a *hgOfficialAccount) cancelLogin(logout bool) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	if logout {
		d := a.disk
		d.Profile = nil
		d.Session = hgCloneSession(d.Session)
		d.Session.Token = ""
		d.Session.Cookies = map[string]string{}
		if e := a.saveSession(d); e != nil {
			return e
		}
		a.disk = d
		a.library = hgOfficialLibrary{}
		a.syncError = ""
	}
	a.generation++
	if a.cancel != nil {
		a.cancel()
	}
	a.attempt = nil
	a.loginError = ""
	return nil
}
func (a *hgOfficialAccount) begin(ctx context.Context) (context.Context, *hgAccountHTTP, uint64, func(), error) {
	if !a.operation.TryLock() {
		return nil, nil, 0, nil, errors.New("红果账号操作正在进行，请稍候")
	}
	a.mu.Lock()
	ctx, cancel := context.WithCancel(ctx)
	a.cancel = cancel
	a.busy = true
	generation := a.generation
	client := hgNewAccountHTTP(a.downloader, hgCloneSession(a.disk.Session))
	a.mu.Unlock()
	finish := func() {
		cancel()
		a.mu.Lock()
		a.busy = false
		a.cancel = nil
		a.mu.Unlock()
		a.operation.Unlock()
	}
	return ctx, client, generation, finish, nil
}
func (a *hgOfficialAccount) persistClient(ctx context.Context, c *hgAccountHTTP, g uint64) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	if ctx.Err() != nil || a.generation != g {
		return errors.New("红果账号操作已取消")
	}
	disk := a.disk
	disk.Session = hgCloneSession(c.session)
	if e := a.saveSession(disk); e != nil {
		return e
	}
	a.disk = disk
	return nil
}
func (a *hgOfficialAccount) sendCode(ctx context.Context, phone string) error {
	phone = strings.TrimSpace(strings.TrimPrefix(phone, "+86"))
	if !hgPhone.MatchString(phone) {
		return errors.New("请输入正确的中国大陆手机号")
	}
	phone = "+86" + phone
	ctx, c, g, finish, e := a.begin(ctx)
	if e != nil {
		return e
	}
	defer finish()
	a.mu.Lock()
	if a.disk.Profile != nil || time.Now().Before(a.retry) {
		a.mu.Unlock()
		return errors.New("请先退出账号，或等待验证码倒计时结束")
	}
	a.loginError = ""
	a.mu.Unlock()
	if e = c.register(ctx); e != nil {
		return e
	}
	if e = a.persistClient(ctx, c, g); e != nil {
		return e
	}
	a.mu.Lock()
	if a.generation != g {
		a.mu.Unlock()
		return errors.New("登录已取消")
	}
	a.retry = time.Now().Add(time.Minute)
	a.attempt = &hgLoginAttempt{Phone: phone, Expires: time.Now().Add(10 * time.Minute)}
	a.mu.Unlock()
	payload, e := c.passport(ctx, "/passport/mobile/send_code/v1/", phone, "", nil)
	if e != nil {
		var he *hgAccountHTTPError
		if errors.As(e, &he) {
			a.mu.Lock()
			if a.generation == g {
				if he.Status == 429 {
					wait, _ := strconv.Atoi(he.Retry)
					if wait > 0 && wait <= 3600 {
						a.retry = time.Now().Add(time.Duration(wait) * time.Second)
					}
				} else {
					a.retry = time.Time{}
					a.attempt = nil
				}
			}
			a.mu.Unlock()
		}
		return e
	}
	if !hgPassportSuccess(payload) {
		a.mu.Lock()
		if a.generation == g {
			a.retry = time.Time{}
			a.attempt = nil
		}
		a.mu.Unlock()
		return errors.New("红果未确认验证码已发送，请检查手机号或稍后重试")
	}
	return a.persistClient(ctx, c, g)
}
func (a *hgOfficialAccount) login(ctx context.Context, code string, verify bool) (err error) {
	if !verify && !hgCode.MatchString(code) {
		return errors.New("请输入 4 至 8 位短信验证码")
	}
	ctx, c, g, finish, e := a.begin(ctx)
	if e != nil {
		return e
	}
	defer finish()
	defer func() {
		a.mu.Lock()
		defer a.mu.Unlock()
		if err != nil && g == a.generation && a.disk.Profile == nil {
			a.loginError = publicError(err).Error()
		}
	}()
	a.mu.Lock()
	if a.disk.Profile != nil || a.attempt == nil || !time.Now().Before(a.attempt.Expires) {
		a.mu.Unlock()
		return errors.New("请重新获取验证码")
	}
	attempt := *a.attempt
	a.loginError = ""
	a.mu.Unlock()
	var payload map[string]any
	if verify {
		if attempt.MFA == nil {
			return errors.New("当前没有待完成的短信验证")
		}
		if !hgCode.MatchString(attempt.Code) {
			return errors.New("本次验证码已不可用，请在此重新获取验证码")
		}
		if !attempt.Verified {
			payload, e = c.verifyMFA(ctx, attempt.MFA)
			if e != nil {
				return fmt.Errorf("检查短信验证失败：%w；可在当前页面重试", e)
			}
			attempt.Verified, e = hgUpSMSVerified(payload)
			if saveErr := a.persistLoginAttempt(ctx, c, g, attempt); saveErr != nil {
				return saveErr
			}
			if e != nil {
				if hgVerificationExpired(payload) {
					return a.rejectExpiredLogin(ctx, g, payload)
				}
				return e
			}
			if !attempt.Verified {
				return nil
			}
		}
		payload, e = c.passport(ctx, "/passport/mobile/sms_login/", attempt.Phone, attempt.Code, attempt.MFA)
	} else {
		payload, e = c.passport(ctx, "/passport/mobile/sms_login/", attempt.Phone, code, nil)
	}
	if e != nil {
		return fmt.Errorf("完成登录失败：%w；可在当前页面重试", e)
	}
	data := nestedMap(payload, "data")
	if !hgPassportSuccess(payload) {
		if mfa := hgParseAccountMFA(data); mfa != nil {
			if !verify {
				attempt.Code = code
			}
			if attempt.MFA == nil || attempt.MFA.EncryptUID != mfa.EncryptUID || attempt.MFA.BizParams["sms_code_key"] != mfa.BizParams["sms_code_key"] {
				attempt.Expires = time.Now().Add(5 * time.Minute)
			}
			attempt.MFA, attempt.Verified = mfa, false
			if e = a.persistLoginAttempt(ctx, c, g, attempt); e != nil {
				return e
			}
			if verify {
				return hgPassportFailure(payload, "红果要求再次短信验证，请按当前显示的号码和内容发送后继续检查")
			}
			return nil
		}
		if e = a.persistLoginAttempt(ctx, c, g, attempt); e != nil {
			return e
		}
		if hgVerificationExpired(payload) {
			return a.rejectExpiredLogin(ctx, g, payload)
		}
		if verify {
			return hgPassportFailure(payload, "短信验证已通过，但登录未完成，请在当前页面重试；如需图形验证，请先在官方 App 完成")
		}
		return hgPassportFailure(payload, "红果登录未成功，请检查验证码；如需图形验证，请先在官方 App 完成")
	}
	uid, numeric := mapString(data, "user_id_str"), mapString(data, "user_id")
	if uid == "" {
		uid = numeric
	}
	if !hgValidID(uid) || numeric != "" && numeric != uid || !hgHasCredentials(c.session) {
		return errors.New("红果登录响应缺少有效身份或会话")
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	if g != a.generation || ctx.Err() != nil || !time.Now().Before(attempt.Expires) {
		return errors.New("登录已取消或已超时")
	}
	disk := a.disk
	disk.Session = hgCloneSession(c.session)
	local := strings.TrimPrefix(attempt.Phone, "+86")
	disk.Profile = &hgAccountProfile{UID: uid, Name: firstNonEmpty(mapString(data, "screen_name", "name"), "红果用户"), Phone: local[:3] + "****" + local[len(local)-4:]}
	previousLibrary := a.library
	if e = a.loadLibrary(uid); e != nil {
		return e
	}
	if e = a.saveSession(disk); e != nil {
		a.library = previousLibrary
		return e
	}
	a.disk = disk
	a.attempt = nil
	a.syncError = ""
	a.loginError = ""
	return nil
}
func (a *hgOfficialAccount) requireOwner(uid string) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.disk.Profile == nil || uid == "" || uid != a.disk.Profile.UID {
		return errors.New("红果账号已退出或切换，请重新打开页面")
	}
	return nil
}
func (engine *nativeEngine) nativeAccount(ctx context.Context, input nativeInput) (any, error) {
	a, e := engine.officialAccount(input.Profile)
	if e != nil {
		return nil, e
	}
	var result any
	switch input.Command {
	case "status":
		return a.status(), nil
	case "seasons":
		return a.seasons(ctx, input.Account.ID)
	case "sendCode":
		e = a.sendCode(ctx, input.Account.Phone)
	case "login":
		e = a.login(ctx, input.Account.Code, false)
	case "verifySMS":
		e = a.login(ctx, "", true)
	case "cancel":
		e = a.cancelLogin(false)
	case "logout":
		e = a.cancelLogin(true)
	case "queueProgress":
		e = a.queueProgress(input.Account)
	case "sync":
		e = a.syncHistory(ctx, input.Account.UID)
	case "history":
		warning := ""
		if input.Account.Refresh {
			if err := a.syncHistory(ctx, input.Account.UID); err != nil {
				if ctx.Err() != nil {
					return nil, ctx.Err()
				}
				warning = "获取最新历史失败，暂时显示已保存记录：" + publicError(err).Error()
			}
		}
		a.mu.Lock()
		if a.disk.Profile == nil || input.Account.UID == "" || input.Account.UID != a.disk.Profile.UID {
			e = errors.New("红果账号已退出或切换，请重新打开页面")
		} else {
			rows := []hgOfficialWatch{}
			for _, w := range a.library.History {
				rows = append(rows, w)
			}
			result = map[string]any{"items": rows, "warning": warning}
		}
		a.mu.Unlock()
	case "favorites", "favorite":
		result, e = a.favorites(ctx, input.Command, input.Account)
	case "reservations", "calendar", "reserve":
		result, e = a.reservations(ctx, input.Command, input.Account)
	default:
		e = errors.New("无效的红果账号操作")
	}
	if e != nil {
		return nil, e
	}
	if result != nil {
		return result, nil
	}
	return a.status(), nil
}
