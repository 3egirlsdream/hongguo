package core

import (
	"context"
	"crypto/tls"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"sync"
	"time"
)

type cdnRecoveryKey struct{}

type cdnResponseBody struct {
	io.ReadCloser
	cancel context.CancelFunc
}

func (body *cdnResponseBody) Close() error {
	err := body.ReadCloser.Close()
	body.cancel()
	return err
}

type cdnRoute struct {
	address string
	expires time.Time
}

type cdnTransport struct {
	base       *http.Transport
	resolver   *dnsResolver
	mu         sync.Mutex
	transports map[string]*http.Transport
	preferred  map[string]cdnRoute
	generation uint64
}

func newCDNTransport(base *http.Transport, resolver *dnsResolver) *cdnTransport {
	return &cdnTransport{base: base, resolver: resolver, transports: map[string]*http.Transport{}, preferred: map[string]cdnRoute{}}
}

func (transport *cdnTransport) RoundTrip(request *http.Request) (*http.Response, error) {
	if !cdnCanRecover(request) {
		return transport.base.RoundTrip(request)
	}
	if request.Body != nil {
		defer request.Body.Close()
	}
	var proxyURL *url.URL
	var err error
	if transport.base.Proxy != nil {
		proxyURL, err = transport.base.Proxy(request)
		if err != nil {
			return nil, err
		}
	}
	routeKey := request.URL.Scheme + "://" + request.URL.Host
	if proxyURL != nil {
		routeKey += "|" + proxyURL.String()
	}
	transport.mu.Lock()
	preferred := transport.preferred[routeKey]
	generation := transport.generation
	transport.mu.Unlock()
	tried := map[string]bool{}
	var response *http.Response
	if preferred.address != "" && time.Now().Before(preferred.expires) {
		tried[preferred.address] = true
		response, err = transport.roundTripAddress(request, proxyURL, routeKey, preferred.address)
		if err == nil {
			return response, nil
		}
		transport.mu.Lock()
		if transport.preferred[routeKey] == preferred {
			delete(transport.preferred, routeKey)
		}
		transport.mu.Unlock()
	}
	response, err = cdnRoundTrip(transport.base, request)
	if err == nil {
		return response, nil
	}
	if request.Context().Err() != nil {
		return nil, request.Context().Err()
	}
	lastErr := err
	subnets := []string{"", dnsAlternateSubnet}
	for _, subnet := range subnets {
		lookupCtx, cancel := context.WithTimeout(request.Context(), cdnAttemptBudget(request.Context()))
		entry, lookupErr := transport.resolver.lookupEntry(lookupCtx, request.URL.Hostname(), subnet)
		cancel()
		if lookupErr != nil {
			if request.Context().Err() != nil {
				return nil, request.Context().Err()
			}
			continue
		}
		for _, address := range entry.addresses {
			if tried[address] || len(tried) >= 2 {
				continue
			}
			tried[address] = true
			response, err = transport.roundTripAddress(request, proxyURL, routeKey, address)
			if err == nil {
				transport.mu.Lock()
				if transport.generation == generation {
					transport.preferred[routeKey] = cdnRoute{address: address, expires: entry.expires}
				}
				transport.mu.Unlock()
				return response, nil
			}
			if request.Context().Err() != nil {
				return nil, request.Context().Err()
			}
			lastErr = err
		}
		if len(tried) >= 2 {
			break
		}
	}
	return nil, fmt.Errorf("资源 %s 连接失败（已尝试备用 DNS 解析）: %w", request.URL.Hostname(), publicError(lastErr))
}

func cdnCanRecover(request *http.Request) bool {
	if request.URL.Scheme != "https" && request.URL.Scheme != "http" || net.ParseIP(request.URL.Hostname()) != nil {
		return false
	}
	explicit := request.Context().Value(cdnRecoveryKey{}) == true
	if !protectedCDNHost(request.URL.Hostname()) && request.Context().Value(nativeCoverNetworkKey{}) != true && !explicit {
		return false
	}
	if request.Body != nil && request.Body != http.NoBody && request.GetBody == nil {
		return false
	}
	return request.Method == http.MethodGet || request.Method == http.MethodHead || explicit && request.Method == http.MethodPost && request.GetBody != nil
}

func cdnAttemptBudget(ctx context.Context) time.Duration {
	budget := 4 * time.Second
	if deadline, ok := ctx.Deadline(); ok {
		budget = min(budget, time.Until(deadline)/3)
	}
	return max(budget, time.Millisecond)
}

func cdnRoundTrip(transport *http.Transport, request *http.Request) (*http.Response, error) {
	ctx, cancel := context.WithCancel(request.Context())
	upstream := request.Clone(ctx)
	if request.GetBody != nil {
		body, err := request.GetBody()
		if err != nil {
			cancel()
			return nil, err
		}
		upstream.Body = body
	}
	timer := time.AfterFunc(cdnAttemptBudget(request.Context()), cancel)
	response, err := transport.RoundTrip(upstream)
	timedOut := !timer.Stop()
	if err != nil || timedOut {
		cancel()
		if response != nil {
			response.Body.Close()
		}
		if timedOut && request.Context().Err() == nil {
			return nil, context.DeadlineExceeded
		}
		return nil, err
	}
	response.Request = request
	response.Body = &cdnResponseBody{ReadCloser: response.Body, cancel: cancel}
	return response, nil
}

func (transport *cdnTransport) roundTripAddress(request *http.Request, proxyURL *url.URL, routeKey, address string) (*http.Response, error) {
	pinned := transport.pinnedTransport(request.URL.Hostname(), proxyURL, routeKey, address)
	upstream := request.Clone(request.Context())
	upstream.Host = request.Host
	if upstream.Host == "" {
		upstream.Host = request.URL.Host
	}
	upstream.URL.Host = address
	if port := request.URL.Port(); port != "" {
		upstream.URL.Host = net.JoinHostPort(address, port)
	}
	response, err := cdnRoundTrip(pinned, upstream)
	if response != nil {
		response.Request = request
	}
	return response, err
}

func (transport *cdnTransport) pinnedTransport(host string, proxyURL *url.URL, routeKey, address string) *http.Transport {
	transport.mu.Lock()
	defer transport.mu.Unlock()
	key := routeKey + "|" + address
	if existing := transport.transports[key]; existing != nil {
		return existing
	}
	pinned := transport.base.Clone()
	if pinned.TLSClientConfig == nil {
		// 显式下限 TLS 1.2（Go 1.22 起默认值），避免依赖隐式默认并消除审计噪音。
		pinned.TLSClientConfig = &tls.Config{MinVersion: tls.VersionTLS12}
	}
	pinned.TLSClientConfig.ServerName = host
	pinned.Proxy = http.ProxyURL(proxyURL)
	if proxyURL != nil && proxyURL.Scheme == "https" {
		plainProxy := *proxyURL
		plainProxy.Scheme = "http"
		if plainProxy.Port() == "" {
			plainProxy.Host = net.JoinHostPort(proxyURL.Hostname(), "443")
		}
		pinned.Proxy = http.ProxyURL(&plainProxy)
		pinned.DialContext = transport.tlsProxyDialer(proxyURL.Hostname())
	}
	if len(transport.transports) >= 32 {
		for expiredKey, expiredTransport := range transport.transports {
			expiredTransport.CloseIdleConnections()
			delete(transport.transports, expiredKey)
			break
		}
	}
	transport.transports[key] = pinned
	return pinned
}

func (transport *cdnTransport) tlsProxyDialer(host string) func(context.Context, string, string) (net.Conn, error) {
	return func(ctx context.Context, network, address string) (net.Conn, error) {
		dial := transport.base.DialContext
		if dial == nil {
			dialer := &net.Dialer{Timeout: 10 * time.Second}
			dial = dialer.DialContext
		}
		connection, err := dial(ctx, network, address)
		if err != nil {
			return nil, err
		}
		config := &tls.Config{}
		if transport.base.TLSClientConfig != nil {
			config = transport.base.TLSClientConfig.Clone()
		}
		config.ServerName = host
		config.NextProtos = []string{"http/1.1"}
		secured := tls.Client(connection, config)
		if transport.base.TLSHandshakeTimeout > 0 {
			var cancel context.CancelFunc
			ctx, cancel = context.WithTimeout(ctx, transport.base.TLSHandshakeTimeout)
			defer cancel()
		}
		if err := secured.HandshakeContext(ctx); err != nil {
			connection.Close()
			return nil, err
		}
		return secured, nil
	}
}

func (transport *cdnTransport) CloseIdleConnections() {
	transport.base.CloseIdleConnections()
	transport.resolver.client.CloseIdleConnections()
	transport.resolver.clearCache()
	transport.mu.Lock()
	defer transport.mu.Unlock()
	transport.generation++
	for key, pinned := range transport.transports {
		pinned.CloseIdleConnections()
		delete(transport.transports, key)
	}
	transport.preferred = map[string]cdnRoute{}
}
