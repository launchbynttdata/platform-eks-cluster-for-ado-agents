package proxy

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestAllowedKEDARequest(t *testing.T) {
	tests := []struct {
		name    string
		method  string
		target  string
		allowed bool
	}{
		{name: "pool by name", method: http.MethodGet, target: "/_apis/distributedtask/pools?poolName=agents", allowed: true},
		{name: "pool by id", method: http.MethodGet, target: "/_apis/distributedtask/pools?poolID=1", allowed: true},
		{name: "job requests", method: http.MethodGet, target: "/_apis/distributedtask/pools/1/jobrequests?$top=250", allowed: true},
		{name: "job requests completed count", method: http.MethodGet, target: "/_apis/distributedtask/pools/1/jobrequests?completedRequestCount=0", allowed: true},
		{name: "reject post", method: http.MethodPost, target: "/_apis/distributedtask/pools?poolName=agents", allowed: false},
		{name: "reject extra query", method: http.MethodGet, target: "/_apis/distributedtask/pools?poolName=agents&redirect=https://evil.example", allowed: false},
		{name: "reject non-numeric pool id path", method: http.MethodGet, target: "/_apis/distributedtask/pools/abc/jobrequests", allowed: false},
		{name: "reject encoded slash path", method: http.MethodGet, target: "/_apis/distributedtask/pools%2F1%2Fjobrequests", allowed: false},
		{name: "reject traversal path", method: http.MethodGet, target: "/_apis/distributedtask/pools/1/../jobrequests", allowed: false},
		{name: "reject unrelated path", method: http.MethodGet, target: "/_apis/projects", allowed: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(tt.method, tt.target, nil)
			path := normalizedKEDAPath(req.URL.EscapedPath(), "/org")
			if got := allowedKEDARequest(req.Method, path, req.URL.Query()); got != tt.allowed {
				t.Fatalf("allowedKEDARequest() = %v, want %v", got, tt.allowed)
			}
		})
	}
}

func TestNormalizedKEDAPathStripsConfiguredOrgPrefix(t *testing.T) {
	got := normalizedKEDAPath("/org/_apis/distributedtask/pools", "/org")
	if got != "/_apis/distributedtask/pools" {
		t.Fatalf("path = %q", got)
	}
}
