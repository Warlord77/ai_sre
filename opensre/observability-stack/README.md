# Observability-stack

End-to-end observability sandbox: two Go microservices, Prometheus, Grafana,
Loki, Promtail, and Tempo, all deployed onto your local Kubernetes cluster
(Docker Desktop's built-in K8s). Logs, metrics, and traces are correlated —
clicking a `trace_id` in a log line in Grafana takes you straight to the trace
in Tempo, and from a span you can pivot to its logs in Loki.

## Architecture

```
                ┌────────────────────┐
                │  curl / browser    │
                └─────────┬──────────┘
                          │ HTTP
                          ▼
                  ┌───────────────┐         OTLP traces
                  │   gateway     │──────────────────────┐
                  └───────┬───────┘                      │
                          │ HTTP                         │
                          ▼                              ▼
                  ┌───────────────┐         ┌──────────────────────┐
                  │   backend     │──OTLP──▶│        Tempo         │
                  └─┬─────────┬───┘         └──────────────────────┘
                    │         │
              SQL   │         │   Redis
                    ▼         ▼
            ┌──────────┐  ┌──────────┐
            │ Postgres │  │  Redis   │
            └──────────┘  └──────────┘

   stdout JSON logs ──── Promtail ───▶ Loki
   /metrics endpoints ── Prometheus (kube-prometheus-stack)
```

All three signals land in **Grafana** as data sources:

- **Prometheus** (RED metrics, runtime metrics, kube-state metrics, node-exporter)
- **Loki** (structured JSON logs from every pod, with `trace_id` extracted as a derived field linking to Tempo)
- **Tempo** (distributed traces, with "Logs for this span" pivoting back to Loki)

## Layout

```
observability-stack/
├── services/
│   ├── gateway/          # Service A: HTTP front, calls backend
│   └── backend/          # Service B: HTTP, Postgres (pgx+otel), Redis (otel)
├── charts/app/           # Helm chart: gateway + backend + Postgres + Redis
├── platform/             # values.yaml for each platform Helm chart
├── scripts/verify.sh
├── Makefile
└── README.md
```

## Prerequisites

- Docker Desktop with Kubernetes enabled (Settings → Kubernetes → Enable)
- **Containerd image store enabled** (Settings → General → "Use containerd for pulling and storing images") — without this, K8s pods can't see images you build with `docker build`
- `kubectl` context pointing at `docker-desktop` (this is automatic when Docker Desktop K8s is enabled)
- helm ≥ 3.13
- Go 1.22+ (for `go mod tidy` — runs on the host before image build)
- `jq` and `curl` (for `make demo` and `make verify`)

## Quick start

```sh
make e2e           # platform + app + end-to-end verification
make port-forward  # Grafana on :3000, gateway on :8080
# in another terminal:
make demo          # generate more traffic
```

Or step-by-step:

```sh
make up            # platform + app
make verify        # checks the stack end-to-end (exit code = number of failures)
```

Grafana login: `admin` / `admin` (see `make grafana-password` if you change it).

## Verifying the stack

```sh
make verify        # checks the stack end-to-end and exits non-zero on any failure
```

`make verify` runs against whatever cluster `kubectl` is currently pointing at and checks:

- Both namespaces exist; every pod in each is Ready
- The four required services exist (gateway, prometheus, loki, tempo)
- Gateway is reachable; `/healthz` and `/readyz` return 200 (`/readyz` transitively probes Postgres + Redis)
- `POST /api/items` writes to Postgres; second `GET /api/items/{id}` produces a `cache hit` log line in the backend
- Prometheus has scrape targets in the `app` namespace and `http_requests_total` series, plus Tempo's service-graph metrics
- Loki has logs from the `app` namespace, including `item created` lines and lines with `trace_id` (logs↔traces correlation works)
- Tempo has traces tagged `service.name=gateway` and `service.name=backend`

Output is a checklist with `[ PASS ]` / `[ FAIL ]` per check; the exit code equals the failure count.

## What `make up` does

1. **`make repos`** — adds `prometheus-community` and `grafana` Helm repos
2. **`make platform`** — installs four Helm releases into the `monitoring` namespace:
   - `kps` → kube-prometheus-stack (Prometheus + Grafana + Alertmanager + node-exporter + kube-state-metrics, plus Loki/Tempo wired in as Grafana data sources via `additionalDataSources`)
   - `loki` → Loki single-binary
   - `promtail` → DaemonSet that tails container logs into Loki
   - `tempo` → Tempo single-binary, OTLP HTTP/gRPC receivers, metrics-generator emitting service-graph metrics into Prometheus via remote-write
3. **`make tidy`** — runs `go mod tidy` in both services (populates `go.sum`)
4. **`make build`** — `docker build` for both services. With containerd image store enabled in Docker Desktop, the resulting images are immediately visible to the cluster.
5. **`make deploy`** — installs the `app` Helm release (gateway, backend, Postgres StatefulSet, Redis Deployment, ServiceMonitors)

## Trying it out

After `make port-forward` and `make demo`:

### Logs in Grafana → Explore → Loki

```logql
{namespace="app"} |= "item created"
```

Each log line is JSON with `trace_id` and `span_id` injected by a custom `slog`
handler. The Grafana data source has a derived field that turns `trace_id` into
a clickable link to Tempo.

### Traces in Grafana → Explore → Tempo

Pick `service.name = gateway` and run a search — each `POST /api/items` produces
a trace spanning gateway → backend → Postgres (and on a cache-hit GET, gateway →
backend → Redis). On any span, "Logs for this span" pivots back to Loki.

### Service map

Grafana → Explore → Tempo → **Service Graph** shows gateway → backend →
postgres/redis edges with RPS and latency, generated by Tempo's
metrics-generator and stored in Prometheus.

### Metrics

- App: `http_requests_total`, `http_request_duration_seconds`, `cache_lookups_total`
- Postgres client (pgx): `db.client.*` via otelpgx
- Redis client: `db.redis.*` via redisotel
- Service graph (from Tempo): `traces_service_graph_request_total`,
  `traces_service_graph_request_server_seconds_bucket`

### Useful PromQL

```promql
# Gateway error rate
sum(rate(http_requests_total{job="gateway",status=~"5.."}[1m]))
  /
sum(rate(http_requests_total{job="gateway"}[1m]))

# p95 latency on the create path
histogram_quantile(0.95,
  sum by (le, route) (rate(http_request_duration_seconds_bucket{route="POST /items"}[5m])))

# Cache hit ratio
sum(rate(cache_lookups_total{result="hit"}[5m]))
  /
sum(rate(cache_lookups_total[5m]))
```

## Iterating on code

```sh
# After editing Go source:
make redeploy      # rebuild images, kind load, rollout restart
```

`go mod tidy` only needs to be re-run if you change imports — `make tidy`.

## Tearing down

```sh
make down          # uninstalls all Helm releases and deletes the app + monitoring namespaces
```

The cluster itself stays — `make down` only removes what `make up` installed.

## Production hardening checklist

This stack is intentionally simple for local learning. For production, you'd
want at minimum:

- **Loki**: switch to scalable mode (read/write/backend), object storage (S3/GCS), proper retention and compactor config.
- **Tempo**: distributed mode, object storage, longer retention.
- **Prometheus**: PVC for retention, Thanos or Mimir for long-term + HA.
- **Postgres**: an operator (CloudNativePG, Zalando) with backups, PITR, replicas — not a hand-rolled StatefulSet.
- **Redis**: Sentinel or cluster, persistence policy reviewed (this demo disables AOF/RDB on purpose).
- **Secrets**: External Secrets Operator or sealed-secrets — never values.yaml.
- **Network policy**: default-deny + explicit egress to Postgres/Redis/Tempo.
- **Pod security**: restricted PSA labels, runAsNonRoot (already set), readOnlyRootFilesystem.
- **PDBs and HPAs** on the services.
- **Resource limits** sized from real load tests, not the placeholders here.
- **Ingress + TLS** instead of `kubectl port-forward`.
- **Sampling**: in production you don't keep 100% of traces — configure tail sampling in an OTel collector between apps and Tempo.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Pods stuck in `ErrImagePull` / `ImagePullBackOff` | Docker Desktop's containerd image store is off. Enable it in Docker Desktop → Settings → General → "Use containerd for pulling and storing images", then `make redeploy`. |
| Grafana shows no Loki data | Check `kubectl -n monitoring logs ds/promtail` — promtail must reach `loki:3100`. |
| Tempo Explore returns "no data" | Apps couldn't reach `tempo.monitoring.svc:4318`; check the backend pod env and `kubectl -n monitoring get svc tempo`. |
| `ServiceMonitor` not picked up | Its `release` label must match the kube-prom-stack release name. We default both to `kps`. |
| Service graph empty | Confirm `enableRemoteWriteReceiver: true` on Prometheus and that `tempo` pods log "metrics-generator" pushes succeeding. |
| `make redeploy` doesn't seem to pick up the new code | Same image tag (`:dev`); rollout pulled a cached image. Rebuild already updates the local image; if needed, force a fresh pod with `kubectl -n app delete pod -l app.kubernetes.io/name=backend`. |
