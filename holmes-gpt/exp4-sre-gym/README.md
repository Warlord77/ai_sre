# HolmesGPT — SRE Gym Integration Evaluation

| | |
| --- | --- |
| **Author** | `Sahil Joseph` |
| **Date** | `2026-10-20` |
| **Time invested** | `~5 hours` |
| **Tool version tested** | `0.45.0` |
| **Source / Docs** | [holmesgpt.dev](https://holmesgpt.dev/) · [GitHub](https://github.com/HolmesGPT/holmesgpt) |
| **License** | `Apache 2.0` |
| **Category** | `AI SRE agent` |
| **Builds on** | [Experiment 1 — HolmesGPT v0.30 on iximiuz Labs](../exp1-iximiuz-v0.30/README.md) |

---

## 1. What problem does this tool solve?

This experiment asks: **does HolmesGPT's RCA quality improve when connected to a full observability stack?** Experiment 1 tested HolmesGPT (v0.30) against pre-broken K8s challenges on iximiuz Labs using only K8s API access. That baseline was promising but the agent had no metrics or log context.

Here we wire HolmesGPT v0.45 to the local SRE Gym (`opensre/observability-stack/`) — a three-tier app (gateway → backend → Postgres/Redis) with Prometheus, Loki, Tempo, and Grafana all running — and trigger real alerting chaos scenarios to measure whether the extra data sources change the quality of the investigation.

We also evaluate `mcp-server-kubernetes` as a lightweight alternative for teams that want K8s investigation capability without running a dedicated AI SRE agent.

---

## 2. How it works (architecture)

```
Alertmanager ──► HolmesGPT (Docker)
                  │  ├── kubernetes/core       (kubectl via patched kubeconfig)
                  │  ├── kubernetes/kube-prometheus-stack (PrometheusRules, AlertmanagerConfig)
                  │  ├── kubernetes/logs       (pod logs via kubectl)
                  │  ├── prometheus/metrics    (PromQL queries → localhost:9090)
                  │  ├── grafana/loki          (LogQL via Grafana → Loki)
                  │  ├── grafana/tempo         (trace search via Grafana → Tempo)
                  │  ├── grafana/dashboards    (dashboard metadata)
                  │  └── helm/core             (Helm releases)
                  │
                  └── LLM: openrouter/anthropic/claude-sonnet-4-5
```

**Model:** `openrouter/anthropic/claude-sonnet-4-5` via OpenRouter.

**Deployment:** Docker container with `--net=host` (Linux) or `host.docker.internal` (macOS Docker Desktop). On macOS, `--net=host` does NOT forward host ports into the container — all endpoint URLs must use `host.docker.internal`.

**Data sources accessed:**
- K8s API via kubeconfig (read-only kubectl)
- Prometheus at `http://host.docker.internal:9090` (port-forwarded)
- Grafana at `http://host.docker.internal:3000` (port-forwarded, service account token)
- Alertmanager at `http://host.docker.internal:9093` (port-forwarded)

**K8s MCP server (`mcp-server-kubernetes`):** Separately evaluated as a kubectl-based MCP server. See section 4 (Scenario 4).

---

## 3. Setup and reproduction steps

### Prerequisites

- Docker Desktop with kind cluster `sre-gym` running (see [`../../opensre/observability-stack/`](../../opensre/observability-stack/README.md))
- Port-forwards active: `make port-forward` in `observability-stack/`
- OpenRouter API key
- `node` / `npx` (for `mcp-server-kubernetes`)

### Step-by-step

```bash
cd holmes-gpt/exp4-sre-gym

# 1. Copy env and fill in keys
cp .env.example .env
# Set OPENROUTER_API_KEY and GRAFANA_API_KEY in .env

# 2. Generate a Grafana service account token
curl -s -X POST http://admin:admin@localhost:3000/api/serviceaccounts \
  -H 'Content-Type: application/json' \
  -d '{"name":"holmesgpt","role":"Viewer"}' | jq .id
# then:
curl -s -X POST http://admin:admin@localhost:3000/api/serviceaccounts/<ID>/tokens \
  -H 'Content-Type: application/json' \
  -d '{"name":"holmes-token"}' | jq .key

# 3. Patch kubeconfig for Docker (replaces 127.0.0.1 with host.docker.internal)
kubectl config view --context kind-sre-gym --minify --raw \
  | sed 's|https://127.0.0.1:|https://host.docker.internal:|g' \
  > /tmp/kube-docker.yaml

# 4. Verify toolsets
make toolsets

# 5. Run chaos + investigation
make scenario-redis-down
make scenario-postgres-down
make scenario-backend-crashloop
```

### Known setup gotchas

**1. `prometheus/metrics` and `grafana/*` are disabled by default in v0.45.**
In previous versions these were auto-enabled by setting env vars (`PROMETHEUS_URL`, `GRAFANA_URL`, `GRAFANA_API_KEY`). In v0.45 built-in toolsets are disabled by default and must be explicitly enabled in `~/.holmes/config.yaml`. The required format is:

```yaml
toolsets:
  prometheus/metrics:
    enabled: true
    config:
      prometheus_url: "http://host.docker.internal:9090"
  grafana/loki:
    enabled: true
    config:
      api_url: "http://host.docker.internal:3000"
      api_key: "<service-account-token>"
      grafana_datasource_uid: "loki"   # required for proxied access
```

**2. `--net=host` does not work on macOS Docker Desktop.**
On macOS, Docker containers run inside a Linux VM. `--net=host` gives the VM's network interface, not the Mac's. All service URLs must use `host.docker.internal` instead of `localhost`.

**3. TLS certificate errors for some kubectl operations.**
The kind cluster's TLS certificate is issued for `localhost` and `sre-gym-control-plane`, not `host.docker.internal`. This means `kubectl describe pod` and `kubectl top` fail with x509 errors inside the container. HolmesGPT worked around this by falling back to K8s API JSON queries (`kubernetes_jq_query`) and Loki for logs.

**4. Grafana Loki/Tempo need `grafana_datasource_uid`.**
Without the `grafana_datasource_uid` field, HolmesGPT treats `api_url` as a direct Loki/Tempo endpoint and fails with "Unable to connect". Setting the UID makes it route queries through Grafana's datasource proxy.

**5. Intermittent Prometheus toolset bug.**
A `TypeError: '>' not supported between instances of 'NoneType' and 'int'` in `prometheus.py:1869` caused some range queries to silently fail. The agent caught these errors and fell back to K8s metrics.

---

## 4. Scenarios tested

All scenarios run against the `sre-gym` kind cluster with the observability stack from `../../opensre/observability-stack/`. Load generator was running throughout for baseline metric data.

**Active toolsets in every run:**
`kubernetes/core`, `kubernetes/kube-prometheus-stack`, `kubernetes/logs`, `prometheus/metrics`, `grafana/loki`, `grafana/tempo`, `grafana/dashboards`, `helm/core`

---

### Scenario 1: Redis Down (`AppRedisDown`)

**What I did:**
```bash
kubectl -n app scale deployment/redis --replicas=0
# waited ~90s for alert to fire
holmes investigate alertmanager --alertmanager-url http://host.docker.internal:9093
```

**What I expected:** HolmesGPT identifies Redis at 0 replicas as root cause.

**What actually happened:**

HolmesGPT investigated 3 firing alerts: `AlertmanagerFailedToSendAlerts` (placeholder Slack token), `AppRedisDown`, and `AlertmanagerClusterFailedToSendAlerts`.

For `AppRedisDown`, the agent:
1. Queried Prometheus — `kube_deployment_status_replicas_available{deployment="redis"}` = 0
2. Queried Loki — found the exact Redis shutdown log: `Received SIGTERM scheduling shutdown` at `15:09:36 UTC`
3. Correlated the timeline: Redis went from 1→0 replicas at 15:09:45, alert fired 30s later at 15:10:15
4. Correctly identified this as an **intentional scale-down** (spec replicas = 0), not a crash
5. Recommended: `kubectl scale deployment redis -n app --replicas=1`

For `AlertmanagerFailedToSendAlerts`, it correctly diagnosed the placeholder Slack token (`invalid_auth`) using both Prometheus metrics (100% clientError rate) and Alertmanager logs from Loki.

**Result: Correct RCA. Root cause accurately identified using Prometheus + Loki together.**

**Key difference vs Experiment 1 (no observability):** The exact SIGTERM timestamp and shutdown log were retrieved from Loki rather than requiring a manual `kubectl logs`. The Prometheus timeline showed exactly when replica count dropped, giving a precise incident start time.

---

### Scenario 2: Postgres Down (`AppPostgresDown`)

**What I did:**
```bash
kubectl -n app scale statefulset/postgres --replicas=0
# waited ~90s for alert + cascade
holmes investigate alertmanager --alertmanager-url ... --alertmanager-alertname AppPostgresDown
```

**What I expected:** Root cause identified as StatefulSet scaled to 0.

**What actually happened:**

1. K8s query confirmed StatefulSet has 0 replicas (`spec.replicas=0`, `readyReplicas=null`)
2. Prometheus confirmed: `kube_statefulset_status_replicas_ready{statefulset="postgres"}` = 0
3. Loki retrieved shutdown logs from `postgres-0`: `received fast shutdown request → aborting transactions → database system is shut down` at `15:13:46`
4. Correctly identified this as a clean, orderly shutdown (no OOM, no crash)

**Where it fell short:** The agent listed 4 possible causes (manual deletion, node issue, scale-down, PVC failure) instead of confirming the scale-down directly. Without `kubectl get statefulset postgres -o yaml` (which failed due to TLS), it couldn't confirm `spec.replicas=0` vs `status.replicas=0` distinction.

**Result: Correct RCA (scale to 0) but hedged — listed it as one of 4 possibilities rather than a definitive finding.**

---

### Scenario 3: Backend CrashLoop (`AppPodCrashLooping`)

**What I did:**
```bash
kubectl -n app scale deployment/backend --replicas=0
kubectl -n app set image deployment/backend backend=busybox:1.36
kubectl -n app scale deployment/backend --replicas=1
# waited ~90s for CrashLoopBackOff
holmes investigate alertmanager --alertmanager-url ... --alertmanager-alertname AppPodCrashLooping
```

**What I expected:** HolmesGPT identifies the wrong image (busybox instead of backend binary) as root cause.

**What actually happened:**

HolmesGPT investigated both backend pods. For each:
1. Used Loki to retrieve the full crash history (58,000 char log stream)
2. Identified **two phases** of the incident:
   - **Phase 1 (restarts #4-8):** Redis connection failures — `dial tcp 10.96.73.48:6379: connection refused` — because the Redis pod was restarted from the previous scenario
   - **Phase 2 (restarts #9+):** Postgres DNS resolution failure — `lookup postgres on 10.96.0.10:53: no such host`
3. Correctly identified Redis downtime window (4 minutes, 15:09:36–15:13:37)

**Where it fell short:** The agent **missed the actual root cause** — it did not identify that the `backend` container image was changed to `busybox:1.36`. It focused on connection failures from logs, which were a symptom of the busybox container not running the backend binary. A `kubectl get deployment backend -o yaml` would have revealed the wrong image, but this call failed due to TLS issues.

**Result: Partially correct — correctly traced cascading dependency failures, but missed the wrong image tag as the true root cause.**

---

### Summary

| Scenario | Alerts Firing | Confidence | Correct RCA | Notes |
|----------|---------------|------------|-------------|-------|
| Redis Down | `AppRedisDown` Critical | High | Yes | Prometheus replica metric + Loki SIGTERM log correlated to a precise timeline; identified intentional scale-down. |
| Postgres Down | `AppPostgresDown` Critical | Medium | Yes (hedged) | Clean-shutdown logs from Loki; listed scale-down among 4 possibilities because TLS blocked the StatefulSet spec read. |
| Backend CrashLoop | `AppPodCrashLooping`, `AppBackendDown` Critical | Medium | Partial | Traced cascading Redis/Postgres connection failures from Loki; missed the busybox image swap because TLS blocked the deployment spec read. |

Raw outputs: [`findings/redis-down.txt`](./findings/redis-down.txt), [`findings/postgres-down.txt`](./findings/postgres-down.txt), [`findings/backend-crashloop.txt`](./findings/backend-crashloop.txt).

---

### Scenario 4: `mcp-server-kubernetes` evaluation

`mcp-server-kubernetes@4.1.9` is an MCP server exposing `kubectl` operations to any MCP client (Claude Code, Cursor, etc.).

**What it provides:**
- All standard `kubectl` operations (get, describe, logs, events) as MCP tools
- Works with any kubeconfig context
- No LLM included — it is a pure tool server consumed by an external LLM agent

**How it differs from HolmesGPT:**

| Dimension | HolmesGPT | mcp-server-kubernetes |
|---|---|---|
| LLM included | Yes (configurable) | No — requires an MCP client |
| Prometheus | Native toolset | Not included |
| Grafana / Loki / Tempo | Native toolsets | Not included |
| Alertmanager | Native integration | Not included |
| K8s access | kubectl + K8s API | kubectl |
| Deployment | Docker / pipx | npx / Docker |
| Use case | Alert-driven RCA | Ad-hoc K8s queries from any LLM IDE |

`mcp-server-kubernetes` is not a HolmesGPT replacement — it is a complement. A developer using Claude Code in VS Code can use it for quick kubectl queries without leaving their IDE. HolmesGPT brings the observability integrations (Prometheus, Loki, Tempo) that make it suitable for on-call incident investigation.

---

## 5. Demo

| Demo | Link | Duration |
|---|---|---|
| Redis Down investigation | _TBD_ | — |
| Backend Crashloop investigation | _TBD_ | — |

Raw investigation outputs: [`findings/`](./findings/)

---

## 6. Observations

- **Toolset discovery changed in v0.45.** `prometheus/metrics`, `grafana/loki`, `grafana/tempo`, `grafana/dashboards` are all disabled by default and require explicit YAML config. The previous eval (v0.30) auto-enabled them via env vars. This is a breaking change with no migration note in the docs.
- **macOS Docker Desktop breaks `--net=host`.** HolmesGPT's docs show `--net=host` for all Docker examples. On macOS this silently fails — the container cannot reach any port-forwarded service. Requires `host.docker.internal` substitution and a patched kubeconfig.
- **TLS cert mismatch for kind + host.docker.internal.** kind issues its certificate for `localhost` and `sre-gym-control-plane`. When the kubeconfig server is rewritten to `host.docker.internal`, certain kubectl calls (describe, top) fail with x509 errors. The agent adapts using `kubernetes_jq_query` and Loki, but this degraded the crashloop diagnosis.
- **Prometheus + Loki together are highly effective.** For redis-down and postgres-down, having both metrics (when did replicas drop to 0) and logs (exact shutdown message with timestamp) gave the agent precise, correlated timelines that would require multiple manual tools to reproduce.
- **Loki as a fallback for pod logs.** When `fetch_pod_logs` failed (TLS issues, pod already gone), the agent fell back to Loki queries and retrieved the complete log history. This is a genuine resilience advantage over plain `kubectl logs`.
- **Wrong image detection failed.** The crashloop scenario (busybox replacing the backend image) was not caught. The agent saw connection errors in the logs but couldn't inspect the pod spec because `kubectl describe` and `kubectl get deployment -o yaml` both failed on TLS.
- **Intermittent Prometheus bug.** `TypeError: '>' not supported between instances of 'NoneType' and 'int'` in `prometheus.py:1869` caused range queries to silently return empty results in ~30% of calls. The agent handled it gracefully but this is a latent reliability issue.
- **Code quality:** Active development, weekly releases. v0.45 introduced breaking changes to toolset configuration without docs.
- **Community:** CNCF Sandbox, active Slack, GitHub issues answered within days.
- **Security posture:** Read-only by design. No cluster write operations. All RBAC-scoped to get/list/watch.

---

## 7. Comparison with alternatives

| Dimension | HolmesGPT v0.45 | OpenSRE v0.1 | mcp-server-kubernetes |
|---|---|---|---|
| Prometheus integration | ✅ Native (requires explicit YAML config) | ❌ Grafana auth bug | ❌ Not included |
| Loki / log integration | ✅ Works via Grafana proxy | ❌ No integration | ❌ Not included |
| Alertmanager as alert source | ✅ Native | ✅ Works (format workaround needed) | ❌ Not included |
| Kubernetes API | ✅ Native (TLS quirks on kind) | ❌ No kubectl at all | ✅ Full kubectl |
| Helm | ✅ Reads releases | ❌ Broken | ❌ Not included |
| macOS Docker support | ⚠️ Needs `host.docker.internal` | ✅ Homebrew binary | ✅ npx |
| RCA quality | Good — multi-source correlation | Poor — broken integrations | N/A (no LLM) |
| Setup complexity | Medium (toolset YAML config required) | High (many broken integrations) | Low (npx) |
| Maturity | CNCF Sandbox, active | Public alpha, daily releases | Stable npm package |

---

## 8. Pros

- **Multi-source correlation works.** Prometheus timeline + Loki log content together produce investigations that would require 3–4 manual steps to replicate.
- **Loki as pod log fallback.** When `kubectl logs` fails (pod gone, TLS issue), Loki has the historical logs. The agent uses it automatically.
- **Correct RCA on redis-down and postgres-down.** Exact shutdown timestamps, replica drop moments, and recommended remediation commands were all correct.
- **Graceful tool failure handling.** When Prometheus range queries fail intermittently, the agent recognises the empty result and retries with different queries or alternative data sources.
- **Read-only, RBAC-friendly.** No cluster modifications. Works fine with `get/list/watch` RBAC.

---

## 9. Cons

- **Breaking config change in v0.45.** Toolsets disabled by default with no migration guide. Teams upgrading from v0.30 will find Prometheus/Grafana silently disabled until they add the YAML config.
- **macOS Docker `--net=host` trap.** All official Docker examples use `--net=host`. This silently fails on macOS. Not documented anywhere in HolmesGPT's setup guides.
- **TLS cert mismatch degrades K8s investigation.** `kubectl describe` and `kubectl get -o yaml` fail inside the container when the kubeconfig server address is rewritten to `host.docker.internal`. The wrong-image crashloop root cause was missed entirely as a result.
- **Prometheus toolset bug.** `TypeError: '>' not supported between instances of 'NoneType' and 'int'` silently drops ~30% of Prometheus range query results. Unfixed as of v0.45.
- **Still read-only, still no remediation.** Correct RCA is produced but no `kubectl scale` or `kubectl set image` is applied. On-call engineers still need to act manually.

---

## 10. Cost analysis

All 3 investigation runs used `openrouter/anthropic/claude-sonnet-4-5`.

| Scenario | Tool calls | Est. input tokens | Est. output tokens |
|---|---|---|---|
| Redis Down (3 alerts) | ~30 | ~120K | ~3K |
| Postgres Down (1 alert) | ~16 | ~80K | ~2K |
| Backend Crashloop (2 alerts) | ~26 | ~150K | ~3K |

Approximate cost per investigation session at Claude Sonnet 4.5 pricing via OpenRouter: **$0.40–0.75 per incident**.

Human cost avoided: ~10–15 minutes of manual `kubectl` + Grafana navigation per incident.

---

## 11. Verdict

**Pilot** — re-evaluate in 6–8 weeks focusing on:

1. Whether the `prometheus/metrics` config requirement and macOS `host.docker.internal` issue are documented
2. Whether the Prometheus range query `TypeError` bug is fixed
3. Whether TLS cert handling in the patched kubeconfig scenario is improved (or kind cluster certificates include SANs for `host.docker.internal`)

### Rationale

HolmesGPT v0.45 with full observability integration produces genuinely useful RCA for scale-down type incidents — it correctly correlated Prometheus replica metrics with Loki shutdown logs in both the Redis and Postgres scenarios. The observability context clearly improves investigation quality over the v0.30 baseline (Experiment 1), which had no metrics or log data.

The blockers for production adoption are:
1. The crashloop diagnosis missed the wrong image — the most common real-world incident type — because of TLS cert issues in the Docker + kind + macOS setup.
2. Three setup gotchas (toolset config format, `host.docker.internal`, TLS cert) required significant debugging and are undocumented.

### If Adopt/Pilot — next steps

- Fix the TLS cert mismatch by either (a) patching `/etc/hosts` inside the container or (b) adding `host.docker.internal` as a SAN to the kind cluster certificate
- Test against a real GKE/EKS cluster where these macOS-specific networking issues don't apply
- Evaluate the operator mode (alpha in v0.30, may have progressed) for continuous autonomous monitoring

### If Defer — revisit trigger

Re-evaluate when:
- `prometheus/metrics` is auto-enabled when `PROMETHEUS_URL` is set (regression from v0.30)
- Prometheus range query bug is fixed
- macOS setup is documented in official docs

---

## 12. Issues / PRs filed

Each issue is documented in detail (symptom / root cause / fix) in [`issues.md`](./issues.md).

| # | Type | Summary | Status |
|---|------|---------|--------|
| 1 | Bug/Docs | Built-in toolsets disabled by default in v0.45, no migration note | Workaround — candidate to file |
| 2 | Docs | `--net=host` does not reach host ports on macOS Docker Desktop | Workaround — candidate to file |
| 3 | Setup | kind kubeconfig `127.0.0.1` unreachable from container | Workaround |
| 4 | Bug | TLS x509 SAN mismatch after kubeconfig patch degrades K8s investigation | No fix |
| 5 | Config | `grafana/loki` & `grafana/tempo` need `grafana_datasource_uid` | Fixed (config) |
| 6 | Bug | Prometheus range query `TypeError` drops ~30% of results (`prometheus.py:1869`) | Candidate to file upstream |
| 7 | Behaviour | `bash`/`kubectl` tool calls blocked by approval prompt in piped mode | Workaround |
| 8 | Behaviour | `fetch_pod_logs` empty for crashed pods — Loki fallback works | Workaround |

---

## 13. References

- [HolmesGPT v0.45 docs — data sources](https://holmesgpt.dev/latest/data-sources/)
- [HolmesGPT v0.45 docs — toolset config format](https://holmesgpt.dev/latest/data-sources/builtin-toolsets/)
- [mcp-server-kubernetes@4.1.9 on npm](https://www.npmjs.com/package/mcp-server-kubernetes)
- [opensre/observability-stack README](../../opensre/observability-stack/README.md)
- [Experiment 1 — HolmesGPT v0.30 baseline](../exp1-iximiuz-v0.30/README.md)
- [Experiment 3 — OpenSRE (for Alertmanager/Prometheus integration comparison)](../../opensre/README.md)

---

## Appendix: Raw findings

<details>
<summary>findings/ directory — full HolmesGPT investigation outputs</summary>

- `findings/redis-down.txt` — full tool call trace + RCA for AppRedisDown
- `findings/postgres-down.txt` — full tool call trace + RCA for AppPostgresDown
- `findings/backend-crashloop.txt` — full tool call trace + RCA for AppPodCrashLooping

</details>
