package token

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
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
	if got := err.Error(); got == "" || got == "super-secret" {
		t.Fatalf("unexpected error text: %q", got)
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
