package core

import (
	"context"
	"fmt"
	"net/url"

	"strings"
	"time"
)

type providerMedia struct {
	credentials *providerMediaCredentials
	URL         string
	Referer     string
	Duration    time.Duration
	Playlist    string
	HLSKey      []byte
	CENCKey     []byte
	Quality     int
	Variants    []providerMedia
}

func (d *Downloader) providerBaseURL(source string) string {
	if !nativeSourceAvailable(source) {
		return ""
	}
	return strings.TrimRight(firstNonEmpty(d.cfg.HongguoURL, hongguoBaseURL), "/")
}

func providerSourceForURL(raw string) string {
	parsed, err := url.Parse(raw)
	if err == nil && (strings.EqualFold(parsed.Hostname(), "hongguoduanju.com") || strings.EqualFold(parsed.Hostname(), "www.hongguoduanju.com")) {
		return sourceHongguo
	}
	return ""
}

func (d *Downloader) providerURLCandidates(raw string) []string {
	source := providerSourceForURL(raw)
	if source == "" {
		return []string{raw}
	}
	parsed, _ := url.Parse(raw)
	d.providerMu.Lock()
	preferred := d.providerHosts[source]
	d.providerMu.Unlock()
	var candidates []string
	seen := map[string]bool{}
	add := func(candidate string) {
		if candidate != "" && !seen[candidate] {
			seen[candidate] = true
			candidates = append(candidates, candidate)
		}
	}
	add(rehostProviderURL(parsed, preferred))
	configured := d.providerBaseURL(source)
	add(rehostProviderURL(parsed, configured))
	if providerSourceForURL(configured) == "" {
		return candidates
	}
	add(raw)
	return candidates
}

func (d *Downloader) resolveProviderMedia(ctx context.Context, task Task) (providerMedia, error) {
	source, _, valid := splitProviderDramaID(task.DramaID)
	if !valid || task.Chapter.Source != "" && canonicalProviderSource(task.Chapter.Source) != source {
		return providerMedia{}, errNativeBuildSource
	}
	if strings.HasPrefix(task.Chapter.VideoURL, "hongguo-cenc://") {
		return d.resolveHongguoMedia(ctx, task)
	}
	media := providerMedia{URL: task.Chapter.VideoURL, Referer: firstNonEmpty(task.Chapter.Referer, d.providerBaseURL(source)+"/")}
	if !isProviderHTTPMediaURL(media.URL) {
		return providerMedia{}, fmt.Errorf("红果未返回有效播放地址，请刷新章节")
	}
	parsed, _ := url.Parse(media.URL)
	if strings.HasSuffix(strings.ToLower(parsed.Path), ".m3u8") {
		playlist, finalURL, err := d.fetchMediaPlaylist(ctx, media.URL, media.Referer)
		if err != nil {
			return providerMedia{}, err
		}
		media.Playlist, media.URL, media.Duration = playlist, finalURL, m3u8Duration(playlist)
	}
	return media, nil
}
