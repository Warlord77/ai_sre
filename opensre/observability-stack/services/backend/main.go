package main

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/google/uuid"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"

	"opensre.local/backend/internal/cache"
	"opensre.local/backend/internal/store"
	"opensre.local/backend/internal/telemetry"
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

	cacheHits = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "cache_lookups_total",
		Help: "Cache lookups by outcome.",
	}, []string{"result"})
)

type server struct {
	items *store.Items
	cache *cache.Cache
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg := loadConfig()

	shutdown, err := telemetry.Init(ctx, "backend", cfg.OTLPEndpoint)
	if err != nil {
		slog.Error("init telemetry", "err", err)
		os.Exit(1)
	}
	defer func() {
		sctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = shutdown(sctx)
	}()

	items, err := store.New(ctx, cfg.PostgresDSN)
	if err != nil {
		slog.Error("init postgres", "err", err)
		os.Exit(1)
	}
	defer items.Close()

	if err := items.Migrate(ctx); err != nil {
		slog.Error("migrate", "err", err)
		os.Exit(1)
	}

	rcache, err := cache.New(cfg.RedisAddr)
	if err != nil {
		slog.Error("init redis", "err", err)
		os.Exit(1)
	}
	defer rcache.Close()

	s := &server{items: items, cache: rcache}

	api := http.NewServeMux()
	api.HandleFunc("POST /items", s.metric("POST /items", s.createItem))
	api.HandleFunc("GET /items/{id}", s.metric("GET /items/{id}", s.getItem))

	root := http.NewServeMux()
	root.Handle("/items", otelhttp.NewHandler(api, "backend"))
	root.Handle("/items/", otelhttp.NewHandler(api, "backend"))
	root.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	root.HandleFunc("GET /readyz", func(w http.ResponseWriter, r *http.Request) {
		if err := items.Ping(r.Context()); err != nil {
			http.Error(w, err.Error(), http.StatusServiceUnavailable)
			return
		}
		if err := rcache.Ping(r.Context()); err != nil {
			http.Error(w, err.Error(), http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
	})
	root.Handle("GET /metrics", promhttp.Handler())

	srv := &http.Server{
		Addr:              cfg.Addr,
		Handler:           root,
		ReadHeaderTimeout: 5 * time.Second,
	}

	go func() {
		slog.Info("backend listening", "addr", cfg.Addr)
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

func (s *server) metric(route string, h http.HandlerFunc) http.HandlerFunc {
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

func (s *server) createItem(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, "bad json", http.StatusBadRequest)
		return
	}
	if body.Name == "" {
		http.Error(w, "name required", http.StatusBadRequest)
		return
	}

	it := store.Item{
		ID:        uuid.NewString(),
		Name:      body.Name,
		CreatedAt: time.Now().UTC(),
	}
	if err := s.items.Insert(r.Context(), it); err != nil {
		slog.ErrorContext(r.Context(), "insert", "err", err)
		http.Error(w, "insert failed", http.StatusInternalServerError)
		return
	}
	if err := s.cache.SetItem(r.Context(), it); err != nil {
		slog.WarnContext(r.Context(), "cache set", "err", err)
	}
	slog.InfoContext(r.Context(), "item created", "id", it.ID, "name", it.Name)
	writeJSON(w, http.StatusCreated, it)
}

func (s *server) getItem(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if cached, ok, err := s.cache.GetItem(r.Context(), id); err != nil {
		slog.WarnContext(r.Context(), "cache get", "err", err)
		cacheHits.WithLabelValues("error").Inc()
	} else if ok {
		cacheHits.WithLabelValues("hit").Inc()
		slog.InfoContext(r.Context(), "cache hit", "id", id)
		writeJSON(w, http.StatusOK, cached)
		return
	} else {
		cacheHits.WithLabelValues("miss").Inc()
	}

	it, err := s.items.Get(r.Context(), id)
	if errors.Is(err, store.ErrNotFound) {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	if err != nil {
		slog.ErrorContext(r.Context(), "get", "err", err)
		http.Error(w, "get failed", http.StatusInternalServerError)
		return
	}
	if err := s.cache.SetItem(r.Context(), it); err != nil {
		slog.WarnContext(r.Context(), "cache set", "err", err)
	}
	slog.InfoContext(r.Context(), "item fetched", "id", id)
	writeJSON(w, http.StatusOK, it)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

type config struct {
	Addr         string
	PostgresDSN  string
	RedisAddr    string
	OTLPEndpoint string
}

func loadConfig() config {
	return config{
		Addr:         envOr("ADDR", ":8080"),
		PostgresDSN:  envOr("POSTGRES_DSN", "postgres://app:app@localhost:5432/app?sslmode=disable"),
		RedisAddr:    envOr("REDIS_ADDR", "localhost:6379"),
		OTLPEndpoint: envOr("OTEL_EXPORTER_OTLP_ENDPOINT", "tempo.monitoring.svc:4318"),
	}
}

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
