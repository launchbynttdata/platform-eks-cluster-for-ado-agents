package proxy

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/launchbynttdata/platform-eks-cluster-for-ado-agents/app/ado-keda-proxy/internal/token"
)

type staticTokenProvider struct {
	token token.Token
	err   error
}

func (p staticTokenProvider) Token(context.Context) (token.Token, error) {
	return p.token, p.err
}

func TestHandlerForwardsAllowedRequestWithBearerToken(t *testing.T) {
	var gotPath, gotAuth, gotInboundAuth string
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath = r.URL.String()
		gotAuth = r.Header.Get("Authorization")
		gotInboundAuth = r.Header.Get("X-Original-Authorization")
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{"count": 0, "value": []any{}})
	}))
	defer upstream.Close()

	baseURL, err := url.Parse(upstream.URL + "/org")
	if err != nil {
		t.Fatal(err)
	}
	handler := NewHandler(Options{
		UpstreamBaseURL: baseURL,
		TokenProvider:   staticTokenProvider{token: token.Token{Value: "bearer-token", ExpiresAt: time.Now().Add(time.Hour)}},
		Client:          upstream.Client(),
		Logger:          discardLogger(),
		Version:         "v1.2.3",
		Commit:          "abc123",
	})

	req := httptest.NewRequest(http.MethodGet, "/org/_apis/distributedtask/pools/42/jobrequests?$top=250", nil)
	req.Header.Set("Authorization", "Basic dummy")
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", rec.Code, rec.Body.String())
	}
	if gotPath != "/org/_apis/distributedtask/pools/42/jobrequests?$top=250" {
		t.Fatalf("upstream path = %q", gotPath)
	}
	if gotAuth != "Bearer bearer-token" {
		t.Fatalf("Authorization = %q", gotAuth)
	}
	if gotInboundAuth != "" {
		t.Fatalf("unexpected forwarded inbound auth marker = %q", gotInboundAuth)
	}
}

func TestHandlerStripsSensitiveUpstreamHeaders(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Authorization", "Bearer upstream-token")
		w.Header().Set("WWW-Authenticate", "Bearer challenge")
		w.Header().Set("Set-Cookie", "session=secret")
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"ok":true}`))
	}))
	defer upstream.Close()

	handler := NewHandler(Options{
		UpstreamBaseURL: mustURL(upstream.URL + "/org"),
		TokenProvider:   staticTokenProvider{token: token.Token{Value: "bearer-token", ExpiresAt: time.Now().Add(time.Hour)}},
		Client:          upstream.Client(),
		Logger:          discardLogger(),
	})

	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/_apis/distributedtask/pools?poolName=agents", nil))

	for _, header := range []string{"Authorization", "WWW-Authenticate", "Set-Cookie"} {
		if got := rec.Header().Get(header); got != "" {
			t.Fatalf("%s header leaked to client: %q", header, got)
		}
	}
	if strings.Contains(rec.Body.String(), "bearer-token") {
		t.Fatalf("response body leaked token: %s", rec.Body.String())
	}
}

func TestHandlerDeniesUnexpectedPath(t *testing.T) {
	handler := NewHandler(Options{
		UpstreamBaseURL: mustURL("https://dev.azure.com/org"),
		TokenProvider:   staticTokenProvider{token: token.Token{Value: "bearer-token", ExpiresAt: time.Now().Add(time.Hour)}},
		Client:          http.DefaultClient,
		Logger:          discardLogger(),
	})

	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/_apis/projects", nil))

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", rec.Code)
	}
}

func TestHandlerReadinessUsesTokenProvider(t *testing.T) {
	handler := NewHandler(Options{
		UpstreamBaseURL: mustURL("https://dev.azure.com/org"),
		TokenProvider:   staticTokenProvider{token: token.Token{Value: "bearer-token", ExpiresAt: time.Now().Add(time.Hour)}},
		Client:          http.DefaultClient,
		Logger:          discardLogger(),
	})

	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/readyz", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
}

func TestHandlerReadinessFailsWhenTokenProviderFails(t *testing.T) {
	handler := NewHandler(Options{
		UpstreamBaseURL: mustURL("https://dev.azure.com/org"),
		TokenProvider:   staticTokenProvider{err: errors.New("token unavailable")},
		Client:          http.DefaultClient,
		Logger:          discardLogger(),
	})

	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/readyz", nil))

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503", rec.Code)
	}
	if strings.Contains(rec.Body.String(), "token unavailable") {
		t.Fatalf("readiness response leaked provider error: %s", rec.Body.String())
	}
}

func TestHandlerDoesNotDoubleWriteAfterCommittedCopyFailure(t *testing.T) {
	var logs bytes.Buffer
	handler := NewHandler(Options{
		UpstreamBaseURL: mustURL("https://dev.azure.com/org"),
		TokenProvider:   staticTokenProvider{token: token.Token{Value: "bearer-token", ExpiresAt: time.Now().Add(time.Hour)}},
		Client: &http.Client{Transport: roundTripFunc(func(*http.Request) (*http.Response, error) {
			return &http.Response{
				StatusCode: http.StatusOK,
				Header:     make(http.Header),
				Body:       failingBody{},
			}, nil
		})},
		Logger: slog.New(slog.NewJSONHandler(&logs, nil)),
	})

	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/_apis/distributedtask/pools?poolName=agents", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want original upstream status", rec.Code)
	}
	if strings.Contains(rec.Body.String(), "upstream request failed") {
		t.Fatalf("handler appended error after committed response: %q", rec.Body.String())
	}
	if !strings.Contains(logs.String(), "upstream response failed after headers were sent") {
		t.Fatalf("logs = %s, want committed-copy error", logs.String())
	}
}

func TestHandlerLogsDoNotIncludeToken(t *testing.T) {
	var logs bytes.Buffer
	logger := slog.New(slog.NewJSONHandler(&logs, nil))
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte("{}"))
	}))
	defer upstream.Close()

	handler := NewHandler(Options{
		UpstreamBaseURL: mustURL(upstream.URL + "/org"),
		TokenProvider:   staticTokenProvider{token: token.Token{Value: "secret-bearer-token", ExpiresAt: time.Now().Add(time.Hour)}},
		Client:          upstream.Client(),
		Logger:          logger,
	})

	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/_apis/distributedtask/pools?poolName=agents", nil))

	if strings.Contains(logs.String(), "secret-bearer-token") {
		t.Fatalf("logs contain token: %s", logs.String())
	}
}

func mustURL(raw string) *url.URL {
	parsed, err := url.Parse(raw)
	if err != nil {
		panic(err)
	}
	return parsed
}

func discardLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(&bytes.Buffer{}, nil))
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) {
	return f(r)
}

type failingBody struct{}

func (failingBody) Read([]byte) (int, error) {
	return 0, errors.New("copy failed")
}

func (failingBody) Close() error {
	return nil
}

var _ io.ReadCloser = failingBody{}
