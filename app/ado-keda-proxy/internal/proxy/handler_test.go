package proxy

import (
	"bytes"
	"context"
	"encoding/json"
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
