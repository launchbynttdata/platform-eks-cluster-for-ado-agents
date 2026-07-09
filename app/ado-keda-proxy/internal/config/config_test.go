package config

import (
	"strings"
	"testing"
)

func TestLoadFromEnv(t *testing.T) {
	t.Setenv("ADO_ORG_URL", "https://dev.azure.com/example/")
	t.Setenv("AZP_CLIENTID", "client-id")
	t.Setenv("AZP_CLIENTSECRET", "client-secret")
	t.Setenv("AZP_TENANTID", "tenant-id")
	t.Setenv("UPSTREAM_TIMEOUT", "3s")

	cfg, err := LoadFromEnv()
	if err != nil {
		t.Fatalf("LoadFromEnv() error = %v", err)
	}

	if got := cfg.ADOOrgURL.String(); got != "https://dev.azure.com/example" {
		t.Fatalf("ADOOrgURL = %q", got)
	}
	if cfg.ClientID != "client-id" || cfg.ClientSecret != "client-secret" || cfg.TenantID != "tenant-id" {
		t.Fatalf("SPN config not loaded from AZP_* fallbacks")
	}
	if cfg.UpstreamTimeout.String() != "3s" {
		t.Fatalf("UpstreamTimeout = %s", cfg.UpstreamTimeout)
	}
}

func TestLoadFromEnvRejectsInvalidADOURL(t *testing.T) {
	t.Setenv("ADO_ORG_URL", "https://example.com/org")
	t.Setenv("ADO_PROXY_CLIENT_ID", "client-id")
	t.Setenv("ADO_PROXY_CLIENT_SECRET", "client-secret")
	t.Setenv("ADO_PROXY_TENANT_ID", "tenant-id")

	_, err := LoadFromEnv()
	if err == nil || !strings.Contains(err.Error(), "dev.azure.com") {
		t.Fatalf("LoadFromEnv() error = %v, want dev.azure.com validation", err)
	}
}

func TestLoadFromEnvRejectsMissingSecrets(t *testing.T) {
	t.Setenv("ADO_ORG_URL", "https://dev.azure.com/example")

	_, err := LoadFromEnv()
	if err == nil {
		t.Fatal("LoadFromEnv() error = nil, want missing credential error")
	}
	for _, want := range []string{"CLIENT_ID", "CLIENT_SECRET", "TENANT_ID"} {
		if !strings.Contains(err.Error(), want) {
			t.Fatalf("LoadFromEnv() error = %v, want %s", err, want)
		}
	}
}
