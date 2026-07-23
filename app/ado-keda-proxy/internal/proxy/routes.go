package proxy

import (
	"encoding/json"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"sync"
)

const (
	maxRawQueryBytes  = 2048
	maxRawQueryFields = 4
)

var jobRequestsPath = regexp.MustCompile(`^/_apis/distributedtask/pools/([0-9]+)/jobrequests$`)

type poolAuthorizer struct {
	poolNames   map[string]struct{}
	poolIDs     map[string]struct{}
	jobsToFetch map[string]struct{}
	learned     sync.Map
}

func newPoolAuthorizer(poolNames, poolIDs, jobsToFetch []string) *poolAuthorizer {
	return &poolAuthorizer{
		poolNames:   toSet(poolNames),
		poolIDs:     toSet(poolIDs),
		jobsToFetch: toSet(jobsToFetch),
	}
}

func normalizedKEDAPath(rawPath, orgPath string) string {
	path := strings.TrimSuffix(rawPath, "/")
	normalizedOrgPath := "/" + strings.Trim(strings.TrimSuffix(orgPath, "/"), "/")
	if normalizedOrgPath != "/" && strings.HasPrefix(path, normalizedOrgPath+"/_apis/") {
		return strings.TrimPrefix(path, normalizedOrgPath)
	}
	return path
}

func parseKEDAQuery(rawQuery string) (url.Values, bool) {
	if len(rawQuery) > maxRawQueryBytes || strings.Count(rawQuery, "&")+1 > maxRawQueryFields {
		return nil, false
	}
	query, err := url.ParseQuery(rawQuery)
	return query, err == nil
}

func (a *poolAuthorizer) allowedKEDARequest(method, path string, query url.Values) bool {
	if method != http.MethodGet {
		return false
	}

	switch {
	case path == "/_apis/distributedtask/pools":
		return a.allowedPoolLookup(query)
	case jobRequestsPath.MatchString(path):
		poolID := jobRequestsPath.FindStringSubmatch(path)[1]
		return a.isAllowedPoolID(poolID) && a.validJobRequestQuery(query)
	default:
		return false
	}
}

func (a *poolAuthorizer) allowedPoolLookup(query url.Values) bool {
	if !hasOnlyQueryKeys(query, "poolName", "poolID") {
		return false
	}
	if poolName, ok := singleQueryValue(query, "poolName"); ok {
		_, allowed := a.poolNames[poolName]
		return allowed && len(query["poolID"]) == 0
	}
	if poolID, ok := singleQueryValue(query, "poolID"); ok {
		return a.isAllowedPoolID(poolID) && len(query["poolName"]) == 0
	}
	return false
}

func (a *poolAuthorizer) isAllowedPoolID(poolID string) bool {
	if _, ok := a.poolIDs[poolID]; ok {
		return true
	}
	_, ok := a.learned.Load(poolID)
	return ok
}

func (a *poolAuthorizer) rememberPoolIDs(query url.Values, body []byte) {
	poolName, ok := singleQueryValue(query, "poolName")
	if !ok {
		return
	}
	if _, allowed := a.poolNames[poolName]; !allowed {
		return
	}

	var response struct {
		Value []struct {
			ID   int64  `json:"id"`
			Name string `json:"name"`
		} `json:"value"`
	}
	if err := json.Unmarshal(body, &response); err != nil {
		return
	}
	for _, pool := range response.Value {
		if pool.ID > 0 && pool.Name == poolName {
			a.learned.Store(strconv.FormatInt(pool.ID, 10), struct{}{})
		}
	}
}

func (a *poolAuthorizer) validJobRequestQuery(query url.Values) bool {
	if !hasOnlyQueryKeys(query, "$top", "completedRequestCount") {
		return false
	}
	if top, ok := singleQueryValue(query, "$top"); ok {
		if len(query["completedRequestCount"]) != 0 {
			return false
		}
		_, allowed := a.jobsToFetch[top]
		return allowed
	}
	if completedCount, ok := singleQueryValue(query, "completedRequestCount"); ok {
		return completedCount == "0" && len(query["$top"]) == 0
	}
	return len(query["$top"]) == 0 && len(query["completedRequestCount"]) == 0
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

func singleQueryValue(query url.Values, key string) (string, bool) {
	values, ok := query[key]
	if !ok || len(values) != 1 || strings.TrimSpace(values[0]) == "" {
		return "", false
	}
	return values[0], true
}

func toSet(values []string) map[string]struct{} {
	set := make(map[string]struct{}, len(values))
	for _, value := range values {
		set[value] = struct{}{}
	}
	return set
}
