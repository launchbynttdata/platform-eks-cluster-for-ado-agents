package token

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestClientCredentialsProvider(t *testing.T) {
	var sawForm atomic.Bool
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Fatalf("method = %s", r.Method)
		}
		if err := r.ParseForm(); err != nil {
			t.Fatalf("ParseForm() error = %v", err)
		}
		if r.Form.Get("client_id") == "client-id" &&
			r.Form.Get("client_secret") == "client-secret" &&
			r.Form.Get("scope") == "scope" &&
			r.Form.Get("grant_type") == "client_credentials" {
			sawForm.Store(true)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"access_token": "access-token",
			"expires_in":   3600,
		})
	}))
	defer server.Close()

	provider := ClientCredentialsProvider{
		Client:       server.Client(),
		TokenURL:     server.URL,
		ClientID:     "client-id",
		ClientSecret: "client-secret",
		Scope:        "scope",
	}

	token, err := provider.Token(context.Background())
	if err != nil {
		t.Fatalf("Token() error = %v", err)
	}
	if token.Value != "access-token" {
		t.Fatalf("token value = %q", token.Value)
	}
	if !sawForm.Load() {
		t.Fatal("token request form did not include expected values")
	}
}

func TestClientCredentialsProviderRedactsEndpointError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"error":             "invalid_client",
			"error_description": "contains sensitive detail",
		})
	}))
	defer server.Close()

	provider := ClientCredentialsProvider{
		Client:       server.Client(),
		TokenURL:     server.URL,
		ClientID:     "client-id",
		ClientSecret: "super-secret",
		Scope:        "scope",
	}

	_, err := provider.Token(context.Background())
	if err == nil {
		t.Fatal("Token() error = nil, want error")
	}
	if got := err.Error(); got == "" || strings.Contains(got, "super-secret") || !strings.Contains(got, "contains sensitive detail") {
		t.Fatalf("unexpected error text: %q", got)
	}
}

func TestClientCredentialsProviderRejectsMissingAccessToken(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"expires_in": 3600})
	}))
	defer server.Close()

	provider := ClientCredentialsProvider{Client: server.Client(), TokenURL: server.URL, ClientID: "client-id", ClientSecret: "client-secret", Scope: "scope"}
	_, err := provider.Token(context.Background())
	if err == nil || !strings.Contains(err.Error(), "access_token") {
		t.Fatalf("Token() error = %v, want missing access_token", err)
	}
}

func TestClientCredentialsProviderRejectsInvalidExpiresIn(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "token", "expires_in": 0})
	}))
	defer server.Close()

	provider := ClientCredentialsProvider{Client: server.Client(), TokenURL: server.URL, ClientID: "client-id", ClientSecret: "client-secret", Scope: "scope"}
	_, err := provider.Token(context.Background())
	if err == nil || !strings.Contains(err.Error(), "expires_in") {
		t.Fatalf("Token() error = %v, want invalid expires_in", err)
	}
}

func TestClientCredentialsProviderReportsTransportError(t *testing.T) {
	provider := ClientCredentialsProvider{
		Client:       &http.Client{Transport: roundTripFunc(func(*http.Request) (*http.Response, error) { return nil, errors.New("dial failed") })},
		TokenURL:     "https://login.microsoftonline.com/tenant/oauth2/v2.0/token",
		ClientID:     "client-id",
		ClientSecret: "client-secret",
		Scope:        "scope",
	}

	_, err := provider.Token(context.Background())
	if err == nil || !strings.Contains(err.Error(), "request token") {
		t.Fatalf("Token() error = %v, want transport error", err)
	}
}

type countingProvider struct {
	count atomic.Int64
	token Token
}

func (p *countingProvider) Token(context.Context) (Token, error) {
	p.count.Add(1)
	return p.token, nil
}

func TestCachingProviderReusesFreshToken(t *testing.T) {
	source := &countingProvider{
		token: Token{Value: "token", ExpiresAt: time.Now().Add(time.Hour)},
	}
	cache := NewCachingProvider(source, 5*time.Minute)

	for i := 0; i < 2; i++ {
		got, err := cache.Token(context.Background())
		if err != nil {
			t.Fatalf("Token() error = %v", err)
		}
		if got.Value != "token" {
			t.Fatalf("token = %q", got.Value)
		}
	}
	if source.count.Load() != 1 {
		t.Fatalf("source calls = %d, want 1", source.count.Load())
	}
}

func TestCachingProviderRefreshesNearExpiry(t *testing.T) {
	source := &countingProvider{
		token: Token{Value: "token", ExpiresAt: time.Now().Add(time.Minute)},
	}
	cache := NewCachingProvider(source, 5*time.Minute)

	for i := 0; i < 2; i++ {
		if _, err := cache.Token(context.Background()); err != nil {
			t.Fatalf("Token() error = %v", err)
		}
	}
	if source.count.Load() != 2 {
		t.Fatalf("source calls = %d, want 2", source.count.Load())
	}
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) {
	return f(r)
}
