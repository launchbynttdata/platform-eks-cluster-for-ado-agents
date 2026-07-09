package config

import (
	"errors"
	"fmt"
	"net/url"
	"os"
	"strings"
	"time"
)

const (
	defaultListenAddress     = ":8080"
	defaultTokenScope        = "499b84ac-1321-427f-aa17-267ca6975798/.default"
	defaultReadHeaderTimeout = 5 * time.Second
	defaultReadTimeout       = 15 * time.Second
	defaultWriteTimeout      = 30 * time.Second
	defaultIdleTimeout       = 60 * time.Second
	defaultUpstreamTimeout   = 20 * time.Second
	defaultTokenRefreshSkew  = 5 * time.Minute
	defaultShutdownTimeout   = 15 * time.Second
)

type Config struct {
	ListenAddress     string
	ADOOrgURL         *url.URL
	TokenURL          string
	TokenScope        string
	ClientID          string
	ClientSecret      string
	TenantID          string
	ReadHeaderTimeout time.Duration
	ReadTimeout       time.Duration
	WriteTimeout      time.Duration
	IdleTimeout       time.Duration
	UpstreamTimeout   time.Duration
	TokenRefreshSkew  time.Duration
	ShutdownTimeout   time.Duration
}

func LoadFromEnv() (Config, error) {
	cfg := Config{
		ListenAddress:     getEnv("LISTEN_ADDRESS", defaultListenAddress),
		TokenScope:        getEnv("TOKEN_SCOPE", defaultTokenScope),
		ClientID:          firstEnv("ADO_PROXY_CLIENT_ID", "AZP_CLIENTID"),
		ClientSecret:      firstEnv("ADO_PROXY_CLIENT_SECRET", "AZP_CLIENTSECRET"),
		TenantID:          firstEnv("ADO_PROXY_TENANT_ID", "AZP_TENANTID"),
		ReadHeaderTimeout: durationEnv("READ_HEADER_TIMEOUT", defaultReadHeaderTimeout),
		ReadTimeout:       durationEnv("READ_TIMEOUT", defaultReadTimeout),
		WriteTimeout:      durationEnv("WRITE_TIMEOUT", defaultWriteTimeout),
		IdleTimeout:       durationEnv("IDLE_TIMEOUT", defaultIdleTimeout),
		UpstreamTimeout:   durationEnv("UPSTREAM_TIMEOUT", defaultUpstreamTimeout),
		TokenRefreshSkew:  durationEnv("TOKEN_REFRESH_SKEW", defaultTokenRefreshSkew),
		ShutdownTimeout:   durationEnv("SHUTDOWN_TIMEOUT", defaultShutdownTimeout),
	}

	adoURL, err := parseADOOrgURL(firstEnv("ADO_ORG_URL", "AZP_URL"))
	if err != nil {
		return Config{}, err
	}
	cfg.ADOOrgURL = adoURL

	if cfg.TenantID != "" {
		cfg.TokenURL = getEnv("TOKEN_URL", fmt.Sprintf("https://login.microsoftonline.com/%s/oauth2/v2.0/token", url.PathEscape(cfg.TenantID)))
	}

	if err := cfg.Validate(); err != nil {
		return Config{}, err
	}
	return cfg, nil
}

func (c Config) Validate() error {
	var errs []error
	if c.ADOOrgURL == nil {
		errs = append(errs, errors.New("ADO_ORG_URL is required"))
	}
	if strings.TrimSpace(c.ClientID) == "" {
		errs = append(errs, errors.New("ADO_PROXY_CLIENT_ID or AZP_CLIENTID is required"))
	}
	if strings.TrimSpace(c.ClientSecret) == "" {
		errs = append(errs, errors.New("ADO_PROXY_CLIENT_SECRET or AZP_CLIENTSECRET is required"))
	}
	if strings.TrimSpace(c.TenantID) == "" {
		errs = append(errs, errors.New("ADO_PROXY_TENANT_ID or AZP_TENANTID is required"))
	}
	if strings.TrimSpace(c.TokenURL) == "" {
		errs = append(errs, errors.New("TOKEN_URL is required"))
	} else if parsed, err := url.Parse(c.TokenURL); err != nil || parsed.Scheme != "https" || parsed.Host == "" {
		errs = append(errs, errors.New("TOKEN_URL must be a valid https URL"))
	}
	if strings.TrimSpace(c.TokenScope) == "" {
		errs = append(errs, errors.New("TOKEN_SCOPE is required"))
	}
	for name, value := range map[string]time.Duration{
		"READ_HEADER_TIMEOUT": c.ReadHeaderTimeout,
		"READ_TIMEOUT":        c.ReadTimeout,
		"WRITE_TIMEOUT":       c.WriteTimeout,
		"IDLE_TIMEOUT":        c.IdleTimeout,
		"UPSTREAM_TIMEOUT":    c.UpstreamTimeout,
		"TOKEN_REFRESH_SKEW":  c.TokenRefreshSkew,
		"SHUTDOWN_TIMEOUT":    c.ShutdownTimeout,
	} {
		if value <= 0 {
			errs = append(errs, fmt.Errorf("%s must be greater than zero", name))
		}
	}
	return errors.Join(errs...)
}

func parseADOOrgURL(raw string) (*url.URL, error) {
	value := strings.TrimRight(strings.TrimSpace(raw), "/")
	if value == "" {
		return nil, errors.New("ADO_ORG_URL is required")
	}
	parsed, err := url.Parse(value)
	if err != nil {
		return nil, fmt.Errorf("ADO_ORG_URL is invalid: %w", err)
	}
	if parsed.Scheme != "https" || strings.EqualFold(parsed.Host, "") {
		return nil, errors.New("ADO_ORG_URL must be an https URL")
	}
	if !strings.EqualFold(parsed.Host, "dev.azure.com") {
		return nil, errors.New("ADO_ORG_URL host must be dev.azure.com")
	}
	if strings.Trim(parsed.Path, "/") == "" || strings.Count(strings.Trim(parsed.Path, "/"), "/") > 0 {
		return nil, errors.New("ADO_ORG_URL must use the form https://dev.azure.com/<org>")
	}
	parsed.RawQuery = ""
	parsed.Fragment = ""
	return parsed, nil
}

func firstEnv(names ...string) string {
	for _, name := range names {
		if value := strings.TrimSpace(os.Getenv(name)); value != "" {
			return value
		}
	}
	return ""
}

func getEnv(name, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}

func durationEnv(name string, fallback time.Duration) time.Duration {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback
	}
	parsed, err := time.ParseDuration(value)
	if err != nil {
		return -1
	}
	return parsed
}
