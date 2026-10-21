# HolmesGPT — SREGym-Lite Benchmark

| | |
| --- | --- |
| **Author** | `Sahil Joseph` |
| **Date** | `2026-10-21` |
| **Tool version tested** | `0.45.0` (Docker image `holmes:latest`) |
| **Benchmark** | [SREGym-Lite](https://github.com/SREGym/SREGym/blob/main/docs/SREGym-Lite.md) — 17 problems |
| **Source / Docs** | [holmesgpt.dev](https://holmesgpt.dev/) · [GitHub](https://github.com/HolmesGPT/holmesgpt) |
| **License** | `Apache 2.0` |
| **Category** | `AI SRE agent` |
| **Builds on** | [Experiment 4 — HolmesGPT on the SRE Gym sandbox](../holmes-gpt-sre-gym/README.md) |

---

## 1. What problem does this answer?

Experiments 1 and 4 ran HolmesGPT on a handful of hand-picked scenarios. This experiment runs it on
[SREGym-Lite](https://github.com/SREGym/SREGym/blob/main/docs/SREGym-Lite.md), a curated, independently
graded set of 17 Kubernetes incidents (network policies, DNS, admission webhooks, Kafka poison pills,
secret rotation, rolling updates, ...). Each problem injects a fault and an LLM judge scores the agent's
diagnosis against the known root cause, so the result is a pass rate rather than an impression.

Only the **diagnosis** stage is run. HolmesGPT is read-only by design and never changes the cluster, so
the mitigation stage would fail by construction.

---

## 2. How it works

```
SREGym conductor ──(fault injected)──► app namespace on kind-sre-gym
      │
      │  GET /status, /get_app
      ▼
client/holmesgpt/driver.py  (runs on host, container_isolation: false)
      │  docker run holmes ask --prompt-file ... --no-interactive
      ▼
HolmesGPT (Docker, --memory 1g)
      ├── kubernetes/core, kubernetes/logs, live-metrics, helm, bash
      │      └── KUBECONFIG = SREGym filtered K8s proxy (https://host.docker.internal:16443)
      └── MCP (SSE): sregym-prometheus, sregym-loki, sregym-jaeger  (host.docker.internal:9954)
      │
      ▼
answer ──► POST /submit ──► LLM judge (score /100, pass/fail)
```

- **Model (agent and judge):** `openrouter/anthropic/claude-sonnet-4-5`
- **Prompt:** application name, namespace(s) and description from SREGym, plus an instruction to end with a
  `ROOT CAUSE` section naming the faulty resources. HolmesGPT is not told what kind of fault it is.
- SREGym's proxy certificate includes a `host.docker.internal` SAN, so the x509 failures from
  Experiment 4 do not occur here.

---

## 3. Setup and reproduction

### Prerequisites

- Docker Desktop with **≥ 8 GB** memory, kind cluster `kind-sre-gym` as current context
- SREGym checkout next to this repo (`../../SREGym`) with submodules: `git submodule update --init --recursive`
- `uv`, `kubectl`, `helm`
- OpenRouter API key

### Steps

```bash
cd holmes-gpt-sregym-lite
cp .env.example .env          # set OPENROUTER_API_KEY
make preflight                # docker, memory, context, uv, key, HolmesGPT image
make run-one PROBLEM=network_policy_block
make run-lite                 # all 17 problems, ~3-4 h
make summary                  # regenerate the results section of this README
make uninstall                # remove the client link + agents.yaml entry from SREGym
```

`make watch` (started alongside `run-lite`) regenerates this README after every finished problem.

### Running on 8 GB

SREGym-Lite asks for 16 GB. To fit a 16 GB Mac with 8 GB given to Docker:

- `--profile svelte` (SREGym built-in): drops Alertmanager, Pushgateway, astronomy-shop's bundled
  OpenSearch/Grafana/Jaeger and the OpenEBS NDM stack, and caps Prometheus at 1 GiB / 2h retention.
  SREGym notes that `svelte` results are **not directly comparable** with `full`-profile results.
- HolmesGPT container capped at `--memory 1g` (it shares the Docker VM with the kind node).
- Problems run one at a time; each problem's app is torn down before the next is deployed.

### Setup gotchas

1. **App charts are a submodule.** Without `git submodule update --init --recursive`, every problem fails
   with `Helm chart_path does not exist`.
2. **Existing cluster vs SREGym's kind config.** `kind-sre-gym` was not created from
   `SREGym/kind/kind-config.yaml` (no `/run/udev` mount, no Calico, single node, stock node image).
   Workaround: `docker exec sre-gym-control-plane mkdir -p /run/udev` (lost on node restart).
3. **Conflicts with an existing monitoring stack.** A pre-installed kube-prometheus-stack / Loki / Promtail
   in `monitoring` collided with SREGym's own install (host port 9100 for node-exporter, cluster-scoped
   `loki-clusterrole`). The `monitoring` namespace was removed so SREGym could install its own stack.
4. **Single node.** Problems that rely on multiple nodes may not reproduce faithfully; they are flagged
   below if they fail to deploy.

---

## 4. Results

<!-- SCORECARD:START -->
### Scorecard

| Problems run | ✅ Passed | ❌ Failed | ⚠️ Not graded | Pass rate | Avg judge score | Avg investigation |
|---:|---:|---:|---:|---:|---:|---:|
| 3/17 | 0 | 3 | 0 | 0% | 0/100 | 2.5 min |
<!-- SCORECARD:END -->

<!-- RESULTS:START -->
**Diagnosis pass rate: 0/3 evaluated** · 3/17 problems run · run `1021_1159` · updated 2026-10-21 12:35

| # | Problem | Diagnosis | Score | Investigation | Judge notes |
|---|---------|-----------|------:|--------------:|-------------|
| 1 | `cronjob_sidecar_blocks_completion_hotel_reservation` | ❌ fail | 0.0 | 2.8 min | Verdict: False (composite=0.00). D1 Fault Localization: 0.00 / D2 Fault Characterization: 0.00 / D3 Scope Precision: 0.00. Weakest dimension: Fault Localization (0.00). Checklist details: [{"id": "D1-Q1", "answer": "No", |
| 2 | `edge_request_filter_cpu_saturation` | ❌ fail | 0.0 | 2.2 min | Verdict: False (composite=0.00). D1 Fault Localization: 0.00 / D2 Fault Characterization: 0.00 / D3 Scope Precision: 0.00. Weakest dimension: Fault Localization (0.00). Checklist details: [{"id": "D1-Q1", "answer": "No", |
| 3 | `network_policy_block` | ❌ fail | 0.0 | 2.4 min | Verdict: False (composite=0.00). D1 Fault Localization: 0.00 / D2 Fault Characterization: 0.00 / D3 Scope Precision: 0.00. Weakest dimension: Fault Localization (0.00). Checklist details: [{"id": "D1-Q1", "answer": "No", |
| 4 | `env_variable_shadowing_astronomy_shop` | not run | | | |
| 5 | `mutating_webhook_resource_limits_social_network` | not run | | | |
| 6 | `finalizer_deadlock_controller_hotel_reservation` | not run | | | |
| 7 | `kafka_poison_pill_hol_block` | not run | | | |
| 8 | `internal_traffic_policy_local_astronomy_shop` | not run | | | |
| 9 | `service_dns_resolution_failure_social_network` | not run | | | |
| 10 | `service_wrong_pod_selection_hotel_reservation` | not run | | | |
| 11 | `namespace_memory_limit` | not run | | | |
| 12 | `valkey_auth_disruption` | not run | | | |
| 13 | `secret_rotation_stale_env_credentials_astronomy_shop` | not run | | | |
| 14 | `unschedulable_incorrect_port_assignment` | not run | | | |
| 15 | `duplicate_pvc_mounts_social_network` | not run | | | |
| 16 | `rolling_update_misconfigured_social_network` | not run | | | |
| 17 | `search_rate_retry_collapse_hotel_reservation` | not run | | | |
<!-- RESULTS:END -->

Raw per-problem HolmesGPT answers: [`results/answers/`](./results/answers/) · full CSV:
[`results/results.csv`](./results/results.csv).

---

## 5. Per-problem observations

Reviewed by hand after each problem finishes (the tables above are generated; this section is not).

**Pattern so far:** HolmesGPT latches onto the loudest error in logs and builds a root cause around it, without enumerating the resource kinds that could carry the fault (CronJobs, NetworkPolicies, proxy config). On hotel-reservation, the brief Consul `connection refused` errors at startup are an attractive decoy; it chose that story in problems 1 and 3.

| # | Problem | Ground truth | What HolmesGPT concluded | Why it missed / how it got there |
|---|---------|--------------|--------------------------|----------------------------------|
| 1 | `cronjob_sidecar_blocks_completion_hotel_reservation` | `CronJob/audit-log-archiver`: a sidecar keeps the Job pod from completing | Missing readiness probes on `consul` and `frontend` cause a startup race and wrk2 timeouts | Never listed CronJobs/Jobs in the namespace (43 tool calls). It anchored on wrk2 timeout counts and Deployment specs, so it built a plausible but unrelated story. Score 0/100 on all three dimensions. |
| 2 | `edge_request_filter_cpu_saturation` | `frontend-proxy`: a new edge/WAF filter regex backtracks catastrophically on long `waf` query values, saturating CPU and timing out healthy paths | `otel-collector-agent` ConfigMap exports to the unqualified `jaeger:4317`, which a previous collector pod failed to resolve | Never checked `frontend-proxy` CPU or its filter config (33 tool calls). It followed the loudest error in the logs. **Possible profile artefact:** under `svelte`, astronomy-shop's bundled Jaeger is disabled, so no `jaeger` Service exists until SREGym creates its ExternalName. The early collector crash HolmesGPT latched onto may not appear under `full`. Score 0/100. |
| 3 | `network_policy_block` | NetworkPolicy `deny-all-recommendation` blocks all traffic to the `recommendation` service | Missing readiness probe on `consul` causes a startup race; frontend gets `connection refused` from Consul | Never queried NetworkPolicies (0 mentions in 45 tool calls). It reached the same wrong answer as problem 1: the frontend's `connection refused` errors at startup, logged in the ~1 s before Consul listens, are benign noise on every hotel-reservation deploy. Score 0/100 (the earlier smoke run of this problem scored 11/100). |
