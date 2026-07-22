package config

import (
	"errors"
	"fmt"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

const (
	defaultListenAddress = ":8080"
	// #nosec G101 -- This is Azure DevOps' public resource application ID, not a credential.
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
	ListenAddress      string
	ADOOrgURL          *url.URL
	TokenURL           string
	TokenScope         string
	ClientID           string
	ClientSecret       string
	TenantID           string
	ReadHeaderTimeout  time.Duration
	ReadTimeout        time.Duration
	WriteTimeout       time.Duration
	IdleTimeout        time.Duration
	UpstreamTimeout    time.Duration
	TokenRefreshSkew   time.Duration
	ShutdownTimeout    time.Duration
	AllowedPoolNames   []string
	AllowedPoolIDs     []string
	AllowedJobsToFetch []string
}

func LoadFromEnv() (Config, error) {
	readHeaderTimeout, err := durationEnv("READ_HEADER_TIMEOUT", defaultReadHeaderTimeout)
	if err != nil {
		return Config{}, err
	}
	readTimeout, err := durationEnv("READ_TIMEOUT", defaultReadTimeout)
	if err != nil {
		return Config{}, err
	}
	writeTimeout, err := durationEnv("WRITE_TIMEOUT", defaultWriteTimeout)
	if err != nil {
		return Config{}, err
	}
	idleTimeout, err := durationEnv("IDLE_TIMEOUT", defaultIdleTimeout)
	if err != nil {
		return Config{}, err
	}
	upstreamTimeout, err := durationEnv("UPSTREAM_TIMEOUT", defaultUpstreamTimeout)
	if err != nil {
		return Config{}, err
	}
	tokenRefreshSkew, err := durationEnv("TOKEN_REFRESH_SKEW", defaultTokenRefreshSkew)
	if err != nil {
		return Config{}, err
	}
	shutdownTimeout, err := durationEnv("SHUTDOWN_TIMEOUT", defaultShutdownTimeout)
	if err != nil {
		return Config{}, err
	}
	allowedPoolNames, err := commaSeparatedEnv("ALLOWED_POOL_NAMES", false)
	if err != nil {
		return Config{}, err
	}
	allowedPoolIDs, err := commaSeparatedEnv("ALLOWED_POOL_IDS", true)
	if err != nil {
		return Config{}, err
	}
	allowedJobsToFetch, err := commaSeparatedEnv("ALLOWED_JOBS_TO_FETCH", true)
	if err != nil {
		return Config{}, err
	}

	cfg := Config{
		ListenAddress:      getEnv("LISTEN_ADDRESS", defaultListenAddress),
		TokenScope:         getEnv("TOKEN_SCOPE", defaultTokenScope),
		ClientID:           firstEnv("ADO_PROXY_CLIENT_ID", "AZP_CLIENTID"),
		ClientSecret:       firstEnv("ADO_PROXY_CLIENT_SECRET", "AZP_CLIENTSECRET"),
		TenantID:           firstEnv("ADO_PROXY_TENANT_ID", "AZP_TENANTID"),
		ReadHeaderTimeout:  readHeaderTimeout,
		ReadTimeout:        readTimeout,
		WriteTimeout:       writeTimeout,
		IdleTimeout:        idleTimeout,
		UpstreamTimeout:    upstreamTimeout,
		TokenRefreshSkew:   tokenRefreshSkew,
		ShutdownTimeout:    shutdownTimeout,
		AllowedPoolNames:   allowedPoolNames,
		AllowedPoolIDs:     allowedPoolIDs,
		AllowedJobsToFetch: allowedJobsToFetch,
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
	} else if !isMicrosoftOnlineHost(parsed.Hostname()) {
		errs = append(errs, errors.New("TOKEN_URL host must be login.microsoftonline.com or a microsoftonline.com subdomain"))
	}
	if strings.TrimSpace(c.TokenScope) == "" {
		errs = append(errs, errors.New("TOKEN_SCOPE is required"))
	}
	if len(c.AllowedPoolNames) == 0 && len(c.AllowedPoolIDs) == 0 {
		errs = append(errs, errors.New("ALLOWED_POOL_NAMES or ALLOWED_POOL_IDS is required"))
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

func commaSeparatedEnv(name string, numeric bool) ([]string, error) {
	raw := strings.TrimSpace(os.Getenv(name))
	if raw == "" {
		return nil, nil
	}

	values := make([]string, 0, strings.Count(raw, ",")+1)
	seen := make(map[string]struct{})
	for _, value := range strings.Split(raw, ",") {
		value = strings.TrimSpace(value)
		if value == "" {
			return nil, fmt.Errorf("%s must not contain empty values", name)
		}
		if numeric {
			parsed, err := strconv.ParseInt(value, 10, 64)
			if err != nil || parsed <= 0 {
				return nil, fmt.Errorf("%s must contain positive numeric pool IDs", name)
			}
		}
		if _, ok := seen[value]; !ok {
			seen[value] = struct{}{}
			values = append(values, value)
		}
	}
	return values, nil
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

func durationEnv(name string, fallback time.Duration) (time.Duration, error) {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback, nil
	}
	parsed, err := time.ParseDuration(value)
	if err != nil {
		return 0, fmt.Errorf("%s is invalid: %w", name, err)
	}
	return parsed, nil
}

func isMicrosoftOnlineHost(host string) bool {
	normalized := strings.ToLower(strings.TrimSpace(host))
	return normalized == "login.microsoftonline.com" || strings.HasSuffix(normalized, ".microsoftonline.com")
}
