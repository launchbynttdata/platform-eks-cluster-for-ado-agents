package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/launchbynttdata/platform-eks-cluster-for-ado-agents/app/ado-keda-proxy/internal/config"
	"github.com/launchbynttdata/platform-eks-cluster-for-ado-agents/app/ado-keda-proxy/internal/proxy"
	"github.com/launchbynttdata/platform-eks-cluster-for-ado-agents/app/ado-keda-proxy/internal/token"
)

var (
	version = "dev"
	commit  = "unknown"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))

	cfg, err := config.LoadFromEnv()
	if err != nil {
		logger.Error("invalid configuration", "error", err)
		os.Exit(1)
	}

	transport := &http.Transport{
		Proxy:                 http.ProxyFromEnvironment,
		MaxIdleConns:          100,
		MaxIdleConnsPerHost:   10,
		IdleConnTimeout:       90 * time.Second,
		TLSHandshakeTimeout:   10 * time.Second,
		ResponseHeaderTimeout: cfg.UpstreamTimeout,
	}
	client := &http.Client{
		Timeout:   cfg.UpstreamTimeout,
		Transport: transport,
	}

	tokenProvider := token.NewCachingProvider(token.ClientCredentialsProvider{
		Client:       client,
		TokenURL:     cfg.TokenURL,
		ClientID:     cfg.ClientID,
		ClientSecret: cfg.ClientSecret,
		Scope:        cfg.TokenScope,
	}, cfg.TokenRefreshSkew)

	handler := proxy.NewHandler(proxy.Options{
		UpstreamBaseURL: cfg.ADOOrgURL,
		TokenProvider:   tokenProvider,
		Client:          client,
		Logger:          logger,
		Version:         version,
		Commit:          commit,
	})

	server := &http.Server{
		Addr:              cfg.ListenAddress,
		Handler:           handler,
		ReadHeaderTimeout: cfg.ReadHeaderTimeout,
		ReadTimeout:       cfg.ReadTimeout,
		WriteTimeout:      cfg.WriteTimeout,
		IdleTimeout:       cfg.IdleTimeout,
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	errCh := make(chan error, 1)
	go func() {
		logger.Info("starting ADO KEDA proxy", "address", cfg.ListenAddress, "version", version, "commit", commit)
		errCh <- server.ListenAndServe()
	}()

	select {
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
		defer cancel()
		if err := server.Shutdown(shutdownCtx); err != nil {
			logger.Error("shutdown failed", "error", err)
			os.Exit(1)
		}
		logger.Info("shutdown complete")
	case err := <-errCh:
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("server failed", "error", err)
			os.Exit(1)
		}
	}
}
