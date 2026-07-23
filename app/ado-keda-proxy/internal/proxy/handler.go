package proxy

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/launchbynttdata/platform-eks-cluster-for-ado-agents/app/ado-keda-proxy/internal/token"
)

type Options struct {
	UpstreamBaseURL    *url.URL
	TokenProvider      token.Provider
	Client             *http.Client
	Logger             *slog.Logger
	Version            string
	Commit             string
	AllowedPoolNames   []string
	AllowedPoolIDs     []string
	AllowedJobsToFetch []string
}

type Handler struct {
	upstreamBaseURL *url.URL
	tokenProvider   token.Provider
	client          *http.Client
	logger          *slog.Logger
	version         string
	commit          string
	authorizer      *poolAuthorizer
}

func NewHandler(opts Options) *Handler {
	logger := opts.Logger
	if logger == nil {
		logger = slog.Default()
	}
	return &Handler{
		upstreamBaseURL: opts.UpstreamBaseURL,
		tokenProvider:   opts.TokenProvider,
		client:          opts.Client,
		logger:          logger,
		version:         opts.Version,
		commit:          opts.Commit,
		authorizer:      newPoolAuthorizer(opts.AllowedPoolNames, opts.AllowedPoolIDs, opts.AllowedJobsToFetch),
	}
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	start := time.Now()
	status := http.StatusOK
	defer func() {
		h.logger.Info("request complete",
			"method", r.Method,
			"path", r.URL.EscapedPath(),
			"status", status,
			"duration_ms", time.Since(start).Milliseconds(),
		)
	}()

	switch r.URL.EscapedPath() {
	case "/healthz":
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok\n"))
		return
	case "/readyz":
		if _, err := h.tokenProvider.Token(r.Context()); err != nil {
			status = http.StatusServiceUnavailable
			http.Error(w, "not ready", http.StatusServiceUnavailable)
			h.logger.Warn("readiness token check failed", "error", err)
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ready\n"))
		return
	}

	kedaPath := normalizedKEDAPath(r.URL.EscapedPath(), h.upstreamBaseURL.EscapedPath())
	query, validQuery := parseKEDAQuery(r.URL.RawQuery)
	if !validQuery || !h.authorizer.allowedKEDARequest(r.Method, kedaPath, query) {
		status = http.StatusNotFound
		http.NotFound(w, r)
		return
	}

	upstreamStatus, committed, err := h.forward(w, r, kedaPath, query)
	if upstreamStatus != 0 {
		status = upstreamStatus
	}
	if err != nil {
		if committed {
			h.logger.Error("upstream response failed after headers were sent", "error", err)
			return
		}
		status = http.StatusBadGateway
		http.Error(w, "upstream request failed", http.StatusBadGateway)
		h.logger.Error("upstream request failed", "error", err)
		return
	}
}

func (h *Handler) forward(w http.ResponseWriter, r *http.Request, kedaPath string, query url.Values) (int, bool, error) {
	tok, err := h.tokenProvider.Token(r.Context())
	if err != nil {
		return 0, false, fmt.Errorf("get token: %w", err)
	}

	upstreamURL := h.upstreamURL(r.URL, kedaPath)
	// #nosec G704 -- upstreamURL starts from the validated dev.azure.com organization URL and replaces only an allowlisted path and query.
	req, err := http.NewRequestWithContext(r.Context(), http.MethodGet, upstreamURL.String(), nil)
	if err != nil {
		return 0, false, fmt.Errorf("create upstream request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+tok.Value)
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", strings.TrimSpace("ado-keda-proxy/"+h.version+" "+h.commit))

	// #nosec G704 -- the client never follows redirects, so the validated Azure DevOps host remains the only upstream destination.
	resp, err := h.client.Do(req)
	if err != nil {
		return 0, false, fmt.Errorf("send upstream request: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()
	if kedaPath == "/_apis/distributedtask/pools" {
		body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20+1))
		if err != nil {
			return 0, false, fmt.Errorf("read pool response: %w", err)
		}
		if len(body) > 1<<20 {
			return 0, false, fmt.Errorf("pool response exceeds 1 MiB limit")
		}
		h.authorizer.rememberPoolIDs(query, body)
		copyResponseHeaders(w.Header(), resp.Header)
		w.WriteHeader(resp.StatusCode)
		if _, err := w.Write(body); err != nil {
			return resp.StatusCode, true, fmt.Errorf("write pool response: %w", err)
		}
		return resp.StatusCode, true, nil
	}

	copyResponseHeaders(w.Header(), resp.Header)
	w.WriteHeader(resp.StatusCode)
	if _, err := io.Copy(w, resp.Body); err != nil {
		return resp.StatusCode, true, fmt.Errorf("copy upstream response: %w", err)
	}
	return resp.StatusCode, true, nil
}

func (h *Handler) upstreamURL(in *url.URL, kedaPath string) *url.URL {
	out := *h.upstreamBaseURL
	out.Path = strings.TrimRight(h.upstreamBaseURL.EscapedPath(), "/") + kedaPath
	out.RawQuery = in.RawQuery
	out.Fragment = ""
	return &out
}

func copyResponseHeaders(dst, src http.Header) {
	for key, values := range src {
		lower := strings.ToLower(key)
		if lower == "authorization" || lower == "www-authenticate" || lower == "set-cookie" {
			continue
		}
		for _, value := range values {
			dst.Add(key, value)
		}
	}
}

func (h *Handler) Ready(ctx context.Context) error {
	_, err := h.tokenProvider.Token(ctx)
	return err
}
