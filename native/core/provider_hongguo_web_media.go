package core

import (
	"encoding/json"
	"io"
	"net/url"
	"strings"

	"golang.org/x/net/html"
)

func hongguoPublicWebMedia(body, base, seriesID, videoID string, page map[string]any) (providerMedia, bool) {
	seo := nestedMap(page, "publicVideoSeo")
	if page["isSuccess"] == false || seo["available"] != true ||
		mapString(seo, "itemId") != videoID || mapString(seo, "seriesId") != seriesID ||
		mapString(nestedMap(page, "seriesDetail"), "series_id") != seriesID {
		return providerMedia{}, false
	}
	player, err := url.Parse(base + "/player/" + seriesID + "/" + videoID)
	if err != nil {
		return providerMedia{}, false
	}
	matches := func(value string) bool {
		u, err := url.Parse(value)
		if err != nil || u.User != nil || u.Scheme != player.Scheme || u.RawQuery != "" || u.Fragment != "" && u.Fragment != "video" {
			return false
		}
		knownHost := strings.EqualFold(u.Host, player.Host) || u.Host == "hongguoduanju.com" || u.Host == "novelquickapp.com"
		return knownHost && (u.Path == player.Path || u.Path == "/player/"+seriesID)
	}
	var find func(any) (providerMedia, bool)
	find = func(value any) (providerMedia, bool) {
		switch v := value.(type) {
		case []any:
			for _, entry := range v {
				if media, ok := find(entry); ok {
					return media, true
				}
			}
		case map[string]any:
			if mapString(v, "@type") == "VideoObject" && matches(mapString(v, "url")) && (mapString(v, "@id") == "" || matches(mapString(v, "@id"))) {
				address := strings.TrimSpace(mapString(v, "contentUrl"))
				if len(address) <= 8192 && isProviderHTTPMediaURL(address) {
					return providerMedia{URL: address, Referer: base + "/"}, true
				}
			}
			if graph, ok := v["@graph"]; ok {
				return find(graph)
			}
		}
		return providerMedia{}, false
	}
	tokens := html.NewTokenizer(strings.NewReader(body))
	for {
		switch tokens.Next() {
		case html.ErrorToken:
			return providerMedia{}, false
		case html.StartTagToken:
			tag := tokens.Token()
			if tag.Data != "script" {
				continue
			}
			isJSON := false
			for _, attr := range tag.Attr {
				isJSON = isJSON || attr.Key == "type" && strings.EqualFold(strings.TrimSpace(attr.Val), "application/ld+json")
			}
			if !isJSON || tokens.Next() != html.TextToken {
				continue
			}
			var value any
			decoder := json.NewDecoder(strings.NewReader(string(tokens.Text())))
			decoder.UseNumber()
			if decoder.Decode(&value) == nil && decoder.Decode(new(any)) == io.EOF {
				if media, ok := find(value); ok {
					return media, true
				}
			}
		}
	}
}
