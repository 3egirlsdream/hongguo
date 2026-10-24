package core

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/md5"
	"crypto/rand"
	"crypto/sha512"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

const hgAccountHost = "https://api5-normal-lq.fqnovel.com"

type hgDeviceIdentity struct {
	CDID       string `json:"cdid"`
	ClientUDID string `json:"clientUdid"`
	OpenUDID   string `json:"openUdid"`
	Created    int64  `json:"created"`
}
type hgAccountSession struct {
	Device     hgDeviceIdentity  `json:"device"`
	DeviceID   string            `json:"deviceId"`
	InstallID  string            `json:"installId"`
	Registered bool              `json:"registered"`
	Cookies    map[string]string `json:"cookies"`
	Token      string            `json:"token"`
}
type hgAccountHTTP struct {
	session hgAccountSession
	http    *http.Client
}

func hgNewAccountHTTP(d *Downloader, session hgAccountSession) *hgAccountHTTP {
	c := *d.client
	c.Timeout = 25 * time.Second
	c.Jar = nil
	c.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	session = hgCloneSession(session)
	return &hgAccountHTTP{session: session, http: &c}
}
func hgCloneSession(s hgAccountSession) hgAccountSession {
	m := map[string]string{}
	for k, v := range s.Cookies {
		m[k] = v
	}
	s.Cookies = m
	return s
}
func hgValidID(s string) bool {
	n, e := strconv.ParseUint(s, 10, 64)
	return e == nil && n > 0 && strconv.FormatUint(n, 10) == s
}
func hgDecodeObject(b []byte) (map[string]any, error) {
	var o map[string]any
	d := json.NewDecoder(bytes.NewReader(b))
	d.UseNumber()
	if d.Decode(&o) != nil || o == nil || d.Decode(new(any)) != io.EOF {
		return nil, errors.New("红果账号响应格式无效")
	}
	return o, nil
}
func hgReadResponse(r *http.Response) ([]byte, error) {
	defer r.Body.Close()
	if r.StatusCode != 200 {
		return nil, &hgAccountHTTPError{Status: r.StatusCode, Retry: r.Header.Get("Retry-After")}
	}
	b, e := io.ReadAll(io.LimitReader(r.Body, 4<<20+1))
	if e != nil || len(b) > 4<<20 || len(b) == 0 {
		return nil, errors.New("红果账号响应为空或读取失败")
	}
	return b, nil
}

type hgAccountHTTPError struct {
	Status int
	Retry  string
}

func (e *hgAccountHTTPError) Error() string {
	return fmt.Sprintf("红果账号服务返回 HTTP %d，请稍后重试", e.Status)
}
func (c *hgAccountHTTP) query() url.Values {
	return url.Values{"aid": {"8662"}, "app_name": {"novelread"}, "version_code": {"73532"}, "version_name": {"7.3.5.32"}, "manifest_version_code": {"73532"}, "update_version_code": {"73532"}, "channel": {"update_64"}, "device_platform": {"android"}, "os": {"android"}, "ssmix": {"a"}, "device_type": {"25053RT47C"}, "device_brand": {"Redmi"}, "language": {"zh"}, "os_api": {"36"}, "os_version": {"16"}, "resolution": {"1280*2772"}, "dpi": {"520"}, "ac": {"wifi"}, "device_id": {c.session.DeviceID}, "iid": {c.session.InstallID}, "cdid": {c.session.Device.CDID}, "openudid": {c.session.Device.OpenUDID}}
}

type hgAccountAPIError struct {
	Code    string
	Message string
}

func (e *hgAccountAPIError) Error() string {
	label := truncate(e.Code, 12)
	if e.Message == "PARAM_INVALID" || e.Message == "TOKEN_EXPIRED" || e.Message == "SESSION_EXPIRED" || e.Message == "USER_NOT_LOGIN" {
		label += " / " + e.Message
	}
	return fmt.Sprintf("红果未确认请求成功（%s），请重试或重新登录", label)
}
func hgAPIError(o map[string]any) error {
	for _, row := range []map[string]any{o, nestedMap(o, "data")} {
		for _, key := range []string{"error_code", "code"} {
			if value, ok := row[key]; ok {
				code := fmt.Sprint(value)
				if code != "0" && code != "" {
					return &hgAccountAPIError{Code: code, Message: mapString(row, "message")}
				}
			}
		}
	}
	return nil
}
func hgPassportSuccess(o map[string]any) bool {
	return mapString(o, "message") == "success" && o["data"] != nil && hgAPIError(o) == nil
}
func (c *hgAccountHTTP) request(ctx context.Context, path, method string, params url.Values, body []byte, contentType string, zipped bool) (map[string]any, error) {
	q := c.query()
	for k, v := range params {
		q[k] = v
	}
	raw, headers, e := hgAuthSign(q, body, time.Now().UnixMilli(), c.session.DeviceID)
	if e != nil {
		return nil, e
	}
	r, e := http.NewRequestWithContext(ctx, method, hgAccountHost+path+"?"+raw, bytes.NewReader(body))
	if e != nil {
		return nil, e
	}
	r.Header = headers
	for k, v := range map[string]string{"User-Agent": hongguoAppUserAgent, "Accept": "application/json", "X-XS-From-Web": "0", "Sdk-Version": "2", "Passport-Sdk-Version": "6031190", "X-SS-DP": "8662", "X-Tt-Store-Region": "cn", "X-Tt-Store-Region-Src": "did"} {
		r.Header.Set(k, v)
	}
	if strings.HasPrefix(path, "/reading/") {
		nonce, err := hgAuthRand()
		if err != nil {
			return nil, err
		}
		r.Header.Set("Lc", "101")
		r.Header.Set("X-Reading-Request", fmt.Sprintf("%d-%d", time.Now().UnixMilli(), nonce))
	}
	if strings.HasPrefix(path, "/passport/") {
		r.Header.Set("Passport-Sdk-Version", "5051452")
		r.Header.Set("X-Vc-Bdturing-Sdk-Version", "4.0.3.cn")
		r.Header.Set("Lc", "101")
	}
	if contentType != "" {
		r.Header.Set("Content-Type", contentType)
	}
	if zipped {
		r.Header.Set("Content-Encoding", "gzip")
		r.Header.Set("Lc", "101")
		nonce, err := hgAuthRand()
		if err != nil {
			return nil, err
		}
		r.Header.Set("X-Reading-Request", fmt.Sprintf("%d-%d", time.Now().UnixMilli(), nonce))
	}
	for k, v := range c.session.Cookies {
		r.AddCookie(&http.Cookie{Name: k, Value: v})
	}
	if region := c.session.Cookies["store-region"]; region != "" {
		r.Header.Set("X-Tt-Store-Region", region)
	}
	if c.session.Token != "" {
		token := []rune(c.session.Token)
		r.Header.Set("X-Tt-Token", string(token[:min(56, len(token))]))
	}
	response, e := c.http.Do(r)
	if e != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, errors.New("无法连接红果账号服务")
	}
	b, e := hgReadResponse(response)
	if e != nil {
		return nil, e
	}
	o, e := hgDecodeObject(b)
	if e != nil {
		return nil, e
	}
	for _, cookie := range response.Cookies() {
		if cookie.MaxAge < 0 {
			delete(c.session.Cookies, cookie.Name)
		} else {
			c.session.Cookies[cookie.Name] = cookie.Value
		}
	}
	if t := response.Header.Get("X-Tt-Token"); t != "" {
		c.session.Token = t
	}
	return o, nil
}
func (c *hgAccountHTTP) json(ctx context.Context, path, method string, q url.Values, body any, zipped bool) (map[string]any, error) {
	var b []byte
	var e error
	kind := ""
	if body != nil {
		b, e = json.Marshal(body)
		if e != nil {
			return nil, e
		}
		kind = "application/json; charset=utf-8"
	}
	if zipped {
		var z bytes.Buffer
		w := gzip.NewWriter(&z)
		if _, e = w.Write(b); e != nil {
			return nil, e
		}
		if e = w.Close(); e != nil {
			return nil, e
		}
		b = z.Bytes()
	}
	o, e := c.request(ctx, path, method, q, b, kind, zipped)
	if e != nil {
		return nil, e
	}
	if _, ok := o["code"]; !ok {
		return nil, errors.New("红果未返回账号操作状态")
	}
	if e = hgAPIError(o); e != nil {
		return nil, fmt.Errorf("%s：%w", path, e)
	}
	return o, nil
}
func hgXor(s string) string {
	b := []byte(s)
	for i := range b {
		b[i] ^= 5
	}
	return hex.EncodeToString(b)
}
func (c *hgAccountHTTP) passport(ctx context.Context, path, phone, code string, mfa *hgAccountMFA) (map[string]any, error) {
	f := url.Values{"mobile": {hgXor(phone)}, "account_sdk_source": {"app"}, "passport_support_flow": {"captcha,verify"}, "mix_mode": {"1"}}
	if code == "" {
		f.Set("auto_read", "0")
		f.Set("unbind_exist", "34")
		f.Set("type", hgXor("24"))
	} else {
		f.Set("code", hgXor(code))
		if mfa != nil {
			for key, value := range mfa.BizParams {
				switch key {
				case "mobile", "code", "mix_mode", "account_sdk_source", "passport_support_flow":
					continue
				case "sms_code_key":
					value = hgXor(value)
				}
				f.Set(key, value)
			}
		}
	}
	return c.request(ctx, path, http.MethodPost, nil, []byte(f.Encode()), "application/x-www-form-urlencoded; charset=UTF-8", false)
}
func hgNewIdentity() (hgDeviceIdentity, error) {
	uuid := func() (string, error) {
		var b [16]byte
		_, e := rand.Read(b[:])
		b[6] = b[6]&15 | 64
		b[8] = b[8]&63 | 128
		return fmt.Sprintf("%x-%x-%x-%x-%x", b[:4], b[4:6], b[6:8], b[8:10], b[10:]), e
	}
	a, e := uuid()
	if e != nil {
		return hgDeviceIdentity{}, e
	}
	b, e := uuid()
	if e != nil {
		return hgDeviceIdentity{}, e
	}
	var open [8]byte
	if _, e = rand.Read(open[:]); e != nil {
		return hgDeviceIdentity{}, e
	}
	return hgDeviceIdentity{a, b, hex.EncodeToString(open[:]), time.Now().UnixMilli()}, nil
}
func hgDeviceKeys(seed []byte) [64]byte {
	h := sha512.Sum512(seed)
	salt := hgAuthHex("4dd4c2e6b83162090e52b3c7a6733ba41cb2462b829ab58a196b39db57177524f49baf7f08e8d68d26a72e37c1a95a2f1f05a51892aef2949732b62a38aadd58")
	return sha512.Sum512(append(h[:], salt...))
}
func hgDeviceCipher(raw, seed []byte) ([]byte, error) {
	var z bytes.Buffer
	w, e := gzip.NewWriterLevel(&z, gzip.BestCompression)
	if e != nil {
		return nil, e
	}
	if _, e = w.Write(raw); e != nil {
		return nil, e
	}
	if e = w.Close(); e != nil {
		return nil, e
	}
	gz := z.Bytes()
	copy(gz, []byte{31, 139, 8, 0, 0, 0, 0, 0, 0, 0})
	h := sha512.Sum512(gz)
	data := hongguoCommentPad(append(h[:], gz...))
	k := hgDeviceKeys(seed)
	block, e := aes.NewCipher(k[:16])
	if e != nil {
		return nil, e
	}
	cipher.NewCBCEncrypter(block, k[16:32]).CryptBlocks(data, data)
	return append(append([]byte{116, 99, 5, 16, 0, 0}, seed...), data...), nil
}
func hgDevicePlain(b []byte) ([]byte, error) {
	if !bytes.HasPrefix(b, []byte{116, 99, 5, 16, 0, 0}) {
		return b, nil
	}
	if len(b) < 118 || (len(b)-38)%16 != 0 {
		return nil, errors.New("设备注册响应无效")
	}
	k := hgDeviceKeys(b[6:38])
	block, _ := aes.NewCipher(k[:16])
	p := append([]byte{}, b[38:]...)
	cipher.NewCBCDecrypter(block, k[16:32]).CryptBlocks(p, p)
	p, e := pkcs7Unpad(p, 16)
	if e != nil || len(p) < 64 {
		return nil, errors.New("设备注册响应校验失败")
	}
	hash := sha512.Sum512(p[64:])
	if !bytes.Equal(hash[:], p[:64]) {
		return nil, errors.New("设备注册响应校验失败")
	}
	g, e := gzip.NewReader(bytes.NewReader(p[64:]))
	if e != nil {
		return nil, e
	}
	defer g.Close()
	out, e := io.ReadAll(io.LimitReader(g, 4<<20+1))
	if len(out) > 4<<20 {
		return nil, errors.New("设备注册响应过大")
	}
	return out, e
}
func (c *hgAccountHTTP) register(ctx context.Context) error {
	if c.session.Registered && hgValidID(c.session.DeviceID) && hgValidID(c.session.InstallID) {
		return nil
	}
	d := c.session.Device
	stamp := time.Now()
	h := map[string]any{"aid": 8662, "access": "wifi", "app_version": "7.3.5.32", "app_version_minor": "", "channel": "update_64", "device_brand": "Redmi", "device_manufacturer": "Redmi", "device_model": "25053RT47C", "device_category": "phone", "device_platform": "android", "os": "Android", "os_api": 36, "os_version": "16", "density_dpi": 520, "display_density": "xxxhdpi", "resolution": "2772x1280", "language": "zh", "timezone": 8, "tz_name": "Asia/Shanghai", "tz_offset": 28800, "region": "CN", "package": "com.phoenix.read", "version_code": 73532, "manifest_version_code": 73532, "update_version_code": 73532, "apk_first_install_time": d.Created, "cdid": d.CDID, "clientudid": d.ClientUDID, "openudid": d.OpenUDID, "cpu_abi": "arm64-v8a", "display_name": "红果短剧", "sdk_version": "3.7.2", "sdk_target_version": 29, "sdk_flavor": "china", "guest_mode": 0, "is_system_app": 0, "not_request_sender": 0, "oaid_may_support": true, "ipv6_list": []string{}, "sim_serial_number": []string{}, "custom": map[string]any{"is_android_fold": 0, "filter_warn": 0, "web_ua": "", "is_android_pad": 0, "client_ipv4": ""}}
	raw, _ := json.Marshal(map[string]any{"magic_tag": "ss_app_log", "header": h, "_gen_time": stamp.UnixMilli()})
	var seed [32]byte
	if _, e := rand.Read(seed[:]); e != nil {
		return e
	}
	body, e := hgDeviceCipher(raw, seed[:])
	if e != nil {
		return e
	}
	q := c.query()
	q.Del("device_id")
	q.Del("iid")
	q.Set("tt_data", "a")
	q.Set("ts", strconv.FormatInt(stamp.Unix(), 10))
	q.Set("_rticket", strconv.FormatInt(stamp.UnixMilli(), 10))
	q.Set("package", "com.phoenix.read")
	r, _ := http.NewRequestWithContext(ctx, http.MethodPost, "https://log.snssdk.com/service/2/device_register/?"+q.Encode(), bytes.NewReader(body))
	for k, v := range map[string]string{"User-Agent": hongguoAppUserAgent, "Content-Type": "application/octet-stream;tt-data=a", "Accept": "application/json; charset=utf-8,application/x-protobuf", "Content-Encoding": "gzip", "X-Tt-Request-Tag": "t=0;n=1", "Log-Encode-Type": "gzip", "Lc": "102", "Sdk-Version": "2", "Passport-Sdk-Version": "60755", "Passport-Sdk-Settings": "device_transfer_s_0,device_transfer_ab_1", "X-SS-DP": "8662", "X-Vc-Bdturing-Sdk-Version": "4.0.3.cn", "X-Tt-Store-Region": "cn", "X-Tt-Store-Region-Src": "did", "X-Khronos": strconv.FormatInt(stamp.Unix(), 10), "X-Argus": base64.StdEncoding.EncodeToString(hgAuthLE(uint32(stamp.Unix()))), "X-SS-Req-Ticket": q.Get("_rticket")} {
		r.Header.Set(k, v)
	}
	digest := md5.Sum(body)
	r.Header.Set("X-SS-STUB", hex.EncodeToString(digest[:]))
	nonce, e := hgAuthRand()
	if e != nil {
		return e
	}
	r.Header.Set("X-Gorgon", hgAuthGorgon(q.Encode(), body, uint32(stamp.Unix()), uint16(nonce)))
	response, e := c.http.Do(r)
	if e != nil {
		return errors.New("红果设备注册连接失败")
	}
	b, e := hgReadResponse(response)
	if e != nil {
		return e
	}
	b, e = hgDevicePlain(b)
	if e != nil {
		return e
	}
	o, e := hgDecodeObject(b)
	if e != nil {
		return e
	}
	did, iid := mapString(o, "device_id_str", "device_id"), mapString(o, "install_id_str", "install_id")
	if !hgValidID(did) || !hgValidID(iid) {
		return errors.New("红果设备注册未返回有效身份")
	}
	c.session.DeviceID, c.session.InstallID, c.session.Registered = did, iid, true
	for _, cookie := range response.Cookies() {
		switch cookie.Name {
		case "store-region", "store-region-src", "ttreq", "odin_tt":
			if cookie.MaxAge >= 0 {
				c.session.Cookies[cookie.Name] = cookie.Value
			}
		}
	}
	c.session.Cookies["install_id"] = iid
	return ctx.Err()
}
