package core

import "context"

type hongguoPlaybackSessionKey struct{}

func (engine *nativeEngine) hongguoPlaybackContext(ctx context.Context, profile string) (context.Context, error) {
	if profile == "" {
		return ctx, nil
	}
	account, err := engine.officialAccount(profile)
	if err != nil {
		return nil, err
	}
	account.mu.Lock()
	defer account.mu.Unlock()
	if account.disk.Profile == nil || !hgHasCredentials(account.disk.Session) {
		return ctx, nil
	}
	return context.WithValue(ctx, hongguoPlaybackSessionKey{}, hgCloneSession(account.disk.Session)), nil
}
