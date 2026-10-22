package core

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/sha512"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

var hongguoMediaAddressFields = []string{"main_url", "backup_url", "backup_url_1", "backup_url_2", "backup_urls", "backup_url_list", "url_list"}

func hongguoOfficialFallbackURL(raw string) bool {
	if len(raw) > 16384 {
		return false
	}
	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "https" || u.User != nil || u.Port() != "" && u.Port() != "443" {
		return false
	}
	host := strings.ToLower(u.Hostname())
	for _, domain := range []string{"fqnovel.com", "snssdk.com"} {
		if host == domain || strings.HasSuffix(host, "."+domain) {
			return true
		}
	}
	return false
}

func (d *Downloader) hongguoFallbackModel(ctx context.Context, value any) (map[string]any, error) {
	if text, ok := value.(string); ok {
		var object map[string]any
		if json.Unmarshal([]byte(text), &object) == nil {
			value = object
		}
	}
	address, _ := value.(string)
	if object, ok := value.(map[string]any); ok {
		address = mapString(object, "fallback_api")
	}
	if rows, ok := value.([]any); ok && len(rows) > 0 {
		address, _ = rows[0].(string)
	}
	if !hongguoOfficialFallbackURL(address) {
		return nil, errors.New("红果 App 返回了无效的官方片源接口")
	}
	r, err := http.NewRequestWithContext(ctx, http.MethodGet, address, nil)
	if err != nil {
		return nil, errors.New("红果 App 片源请求无效")
	}
	r.Header.Set("User-Agent", hongguoAppUserAgent)
	r.Header.Set("Accept", "application/json")
	client := *d.client
	client.Jar = nil
	client.CheckRedirect = func(next *http.Request, previous []*http.Request) error {
		if len(previous) >= 4 || next.Method != http.MethodGet || !hongguoOfficialFallbackURL(next.URL.String()) {
			return errors.New("红果 App 片源接口跳转无效")
		}
		return nil
	}
	response, err := d.doPreparedCatalogRequestWithClient(r, 8*time.Second, nil, &client)
	if err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, errors.New("红果 App 官方片源接口连接失败")
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("红果 App 官方片源接口 HTTP %d", response.StatusCode)
	}
	content, err := io.ReadAll(io.LimitReader(response.Body, (4<<20)+1))
	if err != nil || len(content) > 4<<20 || len(content) == 0 {
		return nil, errors.New("红果 App 官方片源响应为空或读取失败")
	}
	outer, err := hgDecodeObject(content)
	if err != nil {
		return nil, errors.New("红果 App 官方片源响应格式无效")
	}
	info := nestedMap(outer, "video_info")
	for _, object := range []map[string]any{outer, info} {
		if code := mapString(object, "code", "Code"); code != "" && code != "0" {
			return nil, fmt.Errorf("红果 App 官方片源暂不可用（%s）", truncate(code, 20))
		}
	}
	model := nestedMap(info, "data")
	if model == nil {
		return nil, errors.New("红果 App 官方片源未返回播放模型")
	}
	return model, nil
}

func hongguoModelMediaAddresses(model, variant map[string]any) ([]string, error) {
	seedText := mapString(model, "key_seed")
	if seedText == "" {
		return hongguoMediaAddresses(variant), nil
	}
	seed, err := decodeHongguoBase64(seedText)
	if err != nil || len(seed) == 0 || len(seed) > 4096 {
		return nil, errors.New("红果 App 媒体地址种子无效")
	}
	decoded := map[string]any{}
	var lastErr error
	for _, field := range hongguoMediaAddressFields {
		values := anyList(variant[field])
		if text, ok := variant[field].(string); ok {
			values = []any{text}
		}
		var addresses []any
		for _, value := range values {
			text, ok := value.(string)
			if !ok || text == "" {
				continue
			}
			address, err := hongguoDecodeMediaAddress(text, seed)
			if err != nil {
				lastErr = err
				continue
			}
			addresses = append(addresses, address)
		}
		decoded[field] = addresses
	}
	addresses := hongguoMediaAddresses(decoded)
	if len(addresses) == 0 && lastErr != nil {
		return nil, lastErr
	}
	return addresses, nil
}

func hongguoDecodeMediaAddress(value string, seed []byte) (string, error) {
	if len(value) > 16384 {
		return "", errors.New("红果 App 媒体地址过长")
	}
	if isProviderHTTPMediaURL(value) {
		return value, nil
	}
	raw, err := decodeHongguoBase64(value)
	if err != nil {
		return "", errors.New("红果 App 媒体地址编码无效")
	}
	if isProviderHTTPMediaURL(string(raw)) {
		return string(raw), nil
	}
	if len(raw) < 20 || raw[0] != 0xa8 || raw[2] != 1 || raw[3] != 0 {
		return "", errors.New("红果 App 加密媒体地址无效")
	}
	constants, _ := hex.DecodeString("4dd4c2e6b83162090e52b3c7a6733ba41cb2462b829ab58a196b39db57177524f49baf7f08e8d68d26a72e37c1a95a2f1f05a51892aef2949732b62a38aadd58")
	hash := sha512.Sum512(seed)
	material := sha512.Sum512(append(hash[:], constants...))
	block, err := aes.NewCipher(material[:16])
	if err != nil {
		return "", err
	}
	length := (len(raw) - 4) / aes.BlockSize * aes.BlockSize
	plain := make([]byte, length)
	cipher.NewCBCDecrypter(block, material[16:32]).CryptBlocks(plain, raw[4:4+length])
	if unpadded, err := pkcs7Unpad(plain, aes.BlockSize); err == nil {
		plain = unpadded
	}
	address := strings.TrimRight(string(plain), "\x00")
	if len(address) > 8192 || !isProviderHTTPMediaURL(address) {
		return "", errors.New("红果 App 媒体地址解密失败")
	}
	return address, nil
}
