package proxy

import (
	"net/http"
	"net/url"
	"regexp"
	"strings"
)

var jobRequestsPath = regexp.MustCompile(`^/_apis/distributedtask/pools/[0-9]+/jobrequests$`)

func normalizedKEDAPath(rawPath, orgPath string) string {
	path := strings.TrimSuffix(rawPath, "/")
	normalizedOrgPath := "/" + strings.Trim(strings.TrimSuffix(orgPath, "/"), "/")
	if normalizedOrgPath != "/" && strings.HasPrefix(path, normalizedOrgPath+"/_apis/") {
		return strings.TrimPrefix(path, normalizedOrgPath)
	}
	return path
}

func allowedKEDARequest(method, path string, query url.Values) bool {
	if method != http.MethodGet {
		return false
	}

	switch {
	case path == "/_apis/distributedtask/pools":
		return hasOnlyQueryKeys(query, "poolName", "poolID", "api-version")
	case jobRequestsPath.MatchString(path):
		return hasOnlyQueryKeys(query, "$top", "completedRequestCount", "api-version")
	default:
		return false
	}
}

func hasOnlyQueryKeys(query url.Values, allowed ...string) bool {
	allowedSet := make(map[string]struct{}, len(allowed))
	for _, key := range allowed {
		allowedSet[key] = struct{}{}
	}
	for key := range query {
		if _, ok := allowedSet[key]; !ok {
			return false
		}
	}
	return true
}
