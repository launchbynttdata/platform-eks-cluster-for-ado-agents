package proxy

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestAllowedKEDARequest(t *testing.T) {
	authorizer := newPoolAuthorizer([]string{"agents"}, []string{"42"}, []string{"250"})
	tests := []struct {
		name    string
		method  string
		target  string
		allowed bool
	}{
		{name: "configured pool by name", method: http.MethodGet, target: "/_apis/distributedtask/pools?poolName=agents", allowed: true},
		{name: "configured pool by id", method: http.MethodGet, target: "/_apis/distributedtask/pools?poolID=42", allowed: true},
		{name: "configured job requests", method: http.MethodGet, target: "/_apis/distributedtask/pools/42/jobrequests?$top=250", allowed: true},
		{name: "configured job requests completed count", method: http.MethodGet, target: "/_apis/distributedtask/pools/42/jobrequests?completedRequestCount=0", allowed: true},
		{name: "reject pool listing", method: http.MethodGet, target: "/_apis/distributedtask/pools", allowed: false},
		{name: "reject foreign pool name", method: http.MethodGet, target: "/_apis/distributedtask/pools?poolName=foreign", allowed: false},
		{name: "reject foreign pool id", method: http.MethodGet, target: "/_apis/distributedtask/pools/99/jobrequests", allowed: false},
		{name: "reject duplicate pool name", method: http.MethodGet, target: "/_apis/distributedtask/pools?poolName=agents&poolName=foreign", allowed: false},
		{name: "reject duplicate top", method: http.MethodGet, target: "/_apis/distributedtask/pools/42/jobrequests?$top=1&$top=2", allowed: false},
		{name: "reject unconfigured top", method: http.MethodGet, target: "/_apis/distributedtask/pools/42/jobrequests?$top=1001", allowed: false},
		{name: "reject nonzero completed count", method: http.MethodGet, target: "/_apis/distributedtask/pools/42/jobrequests?completedRequestCount=1", allowed: false},
		{name: "reject api version override", method: http.MethodGet, target: "/_apis/distributedtask/pools/42/jobrequests?$top=250&api-version=7.1", allowed: false},
		{name: "reject post", method: http.MethodPost, target: "/_apis/distributedtask/pools?poolName=agents", allowed: false},
		{name: "reject extra query", method: http.MethodGet, target: "/_apis/distributedtask/pools?poolName=agents&redirect=https://evil.example", allowed: false},
		{name: "reject non-numeric pool id path", method: http.MethodGet, target: "/_apis/distributedtask/pools/abc/jobrequests", allowed: false},
		{name: "reject encoded slash path", method: http.MethodGet, target: "/_apis/distributedtask/pools%2F42%2Fjobrequests", allowed: false},
		{name: "reject traversal path", method: http.MethodGet, target: "/_apis/distributedtask/pools/42/../jobrequests", allowed: false},
		{name: "reject unrelated path", method: http.MethodGet, target: "/_apis/projects", allowed: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequestWithContext(context.Background(), tt.method, tt.target, nil)
			path := normalizedKEDAPath(req.URL.EscapedPath(), "/org")
			query, valid := parseKEDAQuery(req.URL.RawQuery)
			if got := valid && authorizer.allowedKEDARequest(req.Method, path, query); got != tt.allowed {
				t.Fatalf("allowedKEDARequest() = %v, want %v", got, tt.allowed)
			}
		})
	}
}

func TestParseKEDAQueryRejectsExcessiveFieldsBeforeParsing(t *testing.T) {
	rawQuery := strings.Repeat("key=value&", maxRawQueryFields) + "key=value"
	if _, valid := parseKEDAQuery(rawQuery); valid {
		t.Fatal("parseKEDAQuery() accepted excessive query fields")
	}
}

func TestPoolLookupLearnsConfiguredPoolID(t *testing.T) {
	authorizer := newPoolAuthorizer([]string{"agents"}, nil, nil)
	query, valid := parseKEDAQuery("poolName=agents")
	if !valid {
		t.Fatal("parseKEDAQuery() = invalid")
	}
	authorizer.rememberPoolIDs(query, []byte(`{"value":[{"id":42,"name":"agents"},{"id":99,"name":"foreign"}]}`))
	if !authorizer.isAllowedPoolID("42") {
		t.Fatal("configured pool lookup did not authorize returned pool ID")
	}
	if authorizer.isAllowedPoolID("99") {
		t.Fatal("pool lookup authorized a pool with a different name")
	}
}

func TestNormalizedKEDAPathStripsConfiguredOrgPrefix(t *testing.T) {
	got := normalizedKEDAPath("/org/_apis/distributedtask/pools", "/org")
	if got != "/_apis/distributedtask/pools" {
		t.Fatalf("path = %q", got)
	}
}
