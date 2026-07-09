package token

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

type Token struct {
	Value     string
	ExpiresAt time.Time
}

type Provider interface {
	Token(ctx context.Context) (Token, error)
}

type ClientCredentialsProvider struct {
	Client       *http.Client
	TokenURL     string
	ClientID     string
	ClientSecret string
	Scope        string
}

func (p ClientCredentialsProvider) Token(ctx context.Context) (Token, error) {
	if p.Client == nil {
		return Token{}, errors.New("token provider requires an HTTP client")
	}
	form := url.Values{}
	form.Set("client_id", p.ClientID)
	form.Set("client_secret", p.ClientSecret)
	form.Set("scope", p.Scope)
	form.Set("grant_type", "client_credentials")

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, p.TokenURL, strings.NewReader(form.Encode()))
	if err != nil {
		return Token{}, fmt.Errorf("create token request: %w", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept", "application/json")

	resp, err := p.Client.Do(req)
	if err != nil {
		return Token{}, fmt.Errorf("request token: %w", err)
	}
	defer resp.Body.Close()

	var body struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int64  `json:"expires_in"`
		Error       string `json:"error"`
		Description string `json:"error_description"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return Token{}, fmt.Errorf("decode token response: %w", err)
	}
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		if body.Error != "" {
			return Token{}, fmt.Errorf("token endpoint returned HTTP %d: %s", resp.StatusCode, body.Error)
		}
		return Token{}, fmt.Errorf("token endpoint returned HTTP %d", resp.StatusCode)
	}
	if body.AccessToken == "" {
		return Token{}, errors.New("token endpoint response did not include access_token")
	}
	if body.ExpiresIn <= 0 {
		return Token{}, errors.New("token endpoint response did not include a valid expires_in")
	}

	return Token{
		Value:     body.AccessToken,
		ExpiresAt: time.Now().Add(time.Duration(body.ExpiresIn) * time.Second),
	}, nil
}

type CachingProvider struct {
	source Provider
	skew   time.Duration
	now    func() time.Time

	mu    sync.Mutex
	token Token
}

func NewCachingProvider(source Provider, skew time.Duration) *CachingProvider {
	return &CachingProvider{
		source: source,
		skew:   skew,
		now:    time.Now,
	}
}

func (p *CachingProvider) Token(ctx context.Context) (Token, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.token.Value != "" && p.now().Add(p.skew).Before(p.token.ExpiresAt) {
		return p.token, nil
	}

	token, err := p.source.Token(ctx)
	if err != nil {
		return Token{}, err
	}
	p.token = token
	return token, nil
}
