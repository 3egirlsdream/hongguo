package core

import (
	"context"
	"errors"
	"strings"
)

type nativeCategory struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

func nativeCatalogKey(source, category string) string {
	source = canonicalProviderSource(source)
	if category = strings.TrimSpace(category); category != "" {
		return source + "|" + category
	}
	return source
}
func validNativeCategory(source, category string) bool {
	if !nativeSourceAvailable(source) {
		return false
	}
	if category == "" {
		return true
	}
	for _, genre := range hongguoAppGenres {
		if category == genre.key {
			return true
		}
	}
	return false
}
func (engine *nativeEngine) nativeCategories(ctx context.Context, source string, force bool) ([]nativeCategory, error) {
	if !nativeSourceAvailable(source) {
		return nil, errors.New("请选择有效站源")
	}
	all := []nativeCategory{{Name: "全部"}}
	for _, genre := range hongguoAppGenres {
		all = append(all, nativeCategory{ID: genre.key, Name: genre.name})
	}
	return all, nil
}
