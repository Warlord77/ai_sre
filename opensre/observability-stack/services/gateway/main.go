package main

import (
	"bytes"
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"

	"opensre.local/gateway/internal/telemetry"
)

var (
	httpRequests = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "http_requests_total",
		Help: "HTTP requests by route and status.",
	}, []string{"route", "status"})

	httpDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "http_request_duration_seconds",
		Help:    "HTTP request duration by route.",
		Buckets: prometheus.DefBuckets,
	}, []string{"route"})
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg := loadConfig()

	shutdown, err := telemetry.Init(ctx, "gateway", cfg.OTLPEndpoint)
	if err != nil {
		slog.Error("init telemetry", "err", err)
		os.Exit(1)
	}
	defer func() {
		sctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = shutdown(sctx)
	}()

	httpClient := &http.Client{
		Transport: otelhttp.NewTransport(http.DefaultTransport),
		Timeout:   5 * time.Second,
	}

	api := http.NewServeMux()
	api.HandleFunc("POST /api/items", instrument("POST /api/items", proxyJSON(httpClient, http.MethodPost, cfg.BackendURL+"/items")))
	api.HandleFunc("GET /api/items/{id}", instrument("GET /api/items/{id}", func(w http.ResponseWriter, r *http.Request) {
		id := r.PathValue("id")
		proxyJSON(httpClient, http.MethodGet, cfg.BackendURL+"/items/"+id)(w, r)
	}))

	root := http.NewServeMux()
	root.Handle("/api/", otelhttp.NewHandler(api, "gateway"))
	root.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	root.HandleFunc("GET /readyz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	root.Handle("GET /metrics", promhttp.Handler())

	srv := &http.Server{
		Addr:              cfg.Addr,
		Handler:           root,
		ReadHeaderTimeout: 5 * time.Second,
	}

	go func() {
		slog.Info("gateway listening", "addr", cfg.Addr, "backend", cfg.BackendURL)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("listen", "err", err)
			os.Exit(1)
		}
	}()

	<-ctx.Done()
	slog.Info("shutting down")
	sctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = srv.Shutdown(sctx)
}

func proxyJSON(client *http.Client, method, url string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var body io.Reader
		if r.Body != nil {
			b, err := io.ReadAll(r.Body)
			if err != nil {
				http.Error(w, "read body", http.StatusBadRequest)
				return
			}
			body = bytes.NewReader(b)
		}
		req, err := http.NewRequestWithContext(r.Context(), method, url, body)
		if err != nil {
			http.Error(w, "build request", http.StatusInternalServerError)
			return
		}
		req.Header.Set("Content-Type", "application/json")
		resp, err := client.Do(req)
		if err != nil {
			slog.ErrorContext(r.Context(), "backend call", "err", err)
			http.Error(w, "upstream error", http.StatusBadGateway)
			return
		}
		defer resp.Body.Close()
		for k, v := range resp.Header {
			w.Header()[k] = v
		}
		w.WriteHeader(resp.StatusCode)
		_, _ = io.Copy(w, resp.Body)
	}
}

func instrument(route string, h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		h(rec, r)
		httpDuration.WithLabelValues(route).Observe(time.Since(start).Seconds())
		httpRequests.WithLabelValues(route, strconv.Itoa(rec.status)).Inc()
	}
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}

type config struct {
	Addr         string
	BackendURL   string
	OTLPEndpoint string
}

func loadConfig() config {
	return config{
		Addr:         envOr("ADDR", ":8080"),
		BackendURL:   envOr("BACKEND_URL", "http://backend:8080"),
		OTLPEndpoint: envOr("OTEL_EXPORTER_OTLP_ENDPOINT", "tempo.monitoring.svc:4318"),
	}
}

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
