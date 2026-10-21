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
4. **ARM64 Envoy OOM (SREGym bug).** On Apple-silicon kind nodes, astronomy-shop's `frontend-proxy` (Envoy) OOMKills at the upstream 65Mi limit. SREGym's ARM64 override doesn't cover it. Added locally to `sregym/service/apps/values/astronomy-shop-arm64.yaml`:
   `components.frontend-proxy.resources.limits.memory: 160Mi`. Problem 4 ran before this fix and is rerun; problem 2's trace shows no Envoy OOM, so it stands.
5. **First social-network deploy is slow.** On a fresh node, social-network's ~27 images pull serially. One hung pull held the namespace in `ContainerCreating` for ~35 min before recovering on its own. Later social-network problems reuse the cached images.
6. **An aborted run can leave fault state behind.** When the judge hung on problem 5's bad submission, SREGym aborted the campaign without running `recover_fault`. Problem 5's five MutatingWebhookConfigurations (one active, four decoys) and the `platform-ops` namespace stayed installed. Every later social-network deploy then got a forced 16Mi memory limit, its MongoDB pods were OOMKilled, and the deploy hung for 75+ min. SREGym's "next startup will clean the remaining fault state" did not remove them. Manual cleanup:
   ```bash
   kubectl delete mutatingwebhookconfiguration cert-manager-webhook gatekeeper-mutating-webhook-configuration \
     istio-sidecar-injector kyverno-resource-mutating-webhook-cfg linkerd-proxy-injector-webhook-config
   kubectl delete ns platform-ops; kubectl -n social-network delete pods --all
   ```
   The remaining problems then ran with `make run-list` (one `run-one` per problem), non-social-network problems first.
7. **Budget.** Eleven HolmesGPT investigations plus judge calls on `claude-sonnet-4-5` used the key's $10 OpenRouter limit (about $1 per problem including retries and the judge). HolmesGPT requests up to 64K output tokens per call, so it fails outright once the remaining balance is below that reservation.
8. **Single node.** Problems that rely on multiple nodes may not reproduce faithfully; they are flagged
   below if they fail to deploy.

---

## 4. Results

<!-- SCORECARD:START -->
### Scorecard

| Problems run | ✅ Passed | ❌ Failed | ⚠️ Not graded | Pass rate | Avg judge score | Avg investigation |
|---:|---:|---:|---:|---:|---:|---:|
| 10/17 | 1 | 6 | 3 | 14% | 19/100 | 2.7 min |
<!-- SCORECARD:END -->

<!-- RESULTS:START -->
**Diagnosis pass rate: 1/7 evaluated** · 10/17 problems run · runs `1021_1159, 1021_1349, 1021_1509, 1021_1540, 1021_1548, 1021_1609, 1021_1616, 1021_1622` · updated 2026-10-21 16:29

| # | Problem | Diagnosis | Score | Investigation | Judge notes |
|---|---------|-----------|------:|--------------:|-------------|
| 1 | `cronjob_sidecar_blocks_completion_hotel_reservation` | ❌ fail | 0.0 | 2.8 min | Verdict: False (composite=0.00). D1 Fault Localization: 0.00 / D2 Fault Characterization: 0.00 / D3 Scope Precision: 0.00. Weakest dimension: Fault Localization (0.00). Checklist details: [{"id": "D1-Q1", "answer": "No", |
| 2 | `edge_request_filter_cpu_saturation` | ❌ fail | 0.0 | 2.2 min | Verdict: False (composite=0.00). D1 Fault Localization: 0.00 / D2 Fault Characterization: 0.00 / D3 Scope Precision: 0.00. Weakest dimension: Fault Localization (0.00). Checklist details: [{"id": "D1-Q1", "answer": "No", |
| 3 | `network_policy_block` | ❌ fail | 0.0 | 2.4 min | Verdict: False (composite=0.00). D1 Fault Localization: 0.00 / D2 Fault Characterization: 0.00 / D3 Scope Precision: 0.00. Weakest dimension: Fault Localization (0.00). Checklist details: [{"id": "D1-Q1", "answer": "No", |
| 4 | `env_variable_shadowing_astronomy_shop` | ⚠️ invalid: ARM64 Envoy OOM at 65Mi (environment bug, fixed; rerun pending) | 56.0 | 1.2 min | Verdict: False (composite=0.56). D1 Fault Localization: 1.00 / D2 Fault Characterization: 0.00 / D3 Scope Precision: 0.67. Weakest dimension: Fault Characterization (0.00). Checklist details: [{"id": "D1-Q1", "answer": " |
| 5 | `mutating_webhook_resource_limits_social_network` | ⚠️ invalid: HolmesGPT crashed on a dropped OpenRouter stream; driver submitted the raw CLI transcript (driver fixed; rerun pending) |  | 0.8 min |  |
| 6 | `finalizer_deadlock_controller_hotel_reservation` | ❌ fail | 0.0 | 3.1 min | Verdict: False (composite=0.00). D1 Fault Localization: 0.00 / D2 Fault Characterization: 0.00 / D3 Scope Precision: 0.00. Weakest dimension: Fault Localization (0.00). Checklist details: [{"id": "D1-Q1", "answer": "No", |
| 7 | `kafka_poison_pill_hol_block` | ✅ pass | 78.0 | 3.6 min | Verdict: True (composite=0.78). D1 Fault Localization: 0.67 / D2 Fault Characterization: 1.00 / D3 Scope Precision: 0.67. Weakest dimension: Fault Localization (0.67). Checklist details: [{"id": "D1-Q1", "answer": "Yes", |
| 8 | `internal_traffic_policy_local_astronomy_shop` | deploy failed |  |  |  |
| 9 | `service_dns_resolution_failure_social_network` | not run | | | |
| 10 | `service_wrong_pod_selection_hotel_reservation` | ❌ fail | 0.0 | 2.2 min | Verdict: False (composite=0.00). D1 Fault Localization: 0.00 / D2 Fault Characterization: 0.00 / D3 Scope Precision: 0.00. Weakest dimension: Fault Localization (0.00). Checklist details: [{"id": "D1-Q1", "answer": "No", |
| 11 | `namespace_memory_limit` | ❌ fail | 56.0 | 2.1 min | Verdict: False (composite=0.56). D1 Fault Localization: 0.00 / D2 Fault Characterization: 1.00 / D3 Scope Precision: 0.67. Weakest dimension: Fault Localization (0.00). Checklist details: [{"id": "D1-Q1", "answer": "No", |
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

**Pattern so far:** HolmesGPT latches onto the loudest error in logs and builds a root cause around it, without enumerating the resource kinds that could carry the fault (CronJobs, NetworkPolicies, proxy config). On hotel-reservation, the brief Consul `connection refused` errors at startup are an attractive decoy; it chose that story in problems 1 and 3. The baseline wrk2 timeout count (~190 per 30 s round) is a second decoy (problems 1, 6). In problem 6 HolmesGPT also invented an "expected" value for a default setting, and it reused the same `rate` QPS story in problem 10. On astronomy-shop, the decoy is the `jaeger` Service, which SREGym turns into an ExternalName pointing at its own collector while leaving the old selector in place. HolmesGPT flagged it in problems 2 and 7.

**What worked (problems 7, 11):** when the fault leaves an explicit error, HolmesGPT finds and explains it well. In problem 7 that was a parse error at a specific offset in a consumer's logs, and in problem 11 an admission rejection (`must specify memory`) in events. In 11 it then blamed the symptom (`search`) over the origin (the quota).

| # | Problem | Ground truth | What HolmesGPT concluded | Why it missed / how it got there |
|---|---------|--------------|--------------------------|----------------------------------|
| 1 | `cronjob_sidecar_blocks_completion_hotel_reservation` | `CronJob/audit-log-archiver`: a sidecar keeps the Job pod from completing | Missing readiness probes on `consul` and `frontend` cause a startup race and wrk2 timeouts | Never listed CronJobs/Jobs in the namespace (43 tool calls). It anchored on wrk2 timeout counts and Deployment specs, so it built a plausible but unrelated story. Score 0/100 on all three dimensions. |
| 2 | `edge_request_filter_cpu_saturation` | `frontend-proxy`: a new edge/WAF filter regex backtracks catastrophically on long `waf` query values, saturating CPU and timing out healthy paths | `otel-collector-agent` ConfigMap exports to the unqualified `jaeger:4317`, which a previous collector pod failed to resolve | Never checked `frontend-proxy` CPU or its filter config (33 tool calls). It followed the loudest error in the logs. **Possible profile artefact:** under `svelte`, astronomy-shop's bundled Jaeger is disabled, so no `jaeger` Service exists until SREGym creates its ExternalName. The early collector crash HolmesGPT latched onto may not appear under `full`. Score 0/100. |
| 3 | `network_policy_block` | NetworkPolicy `deny-all-recommendation` blocks all traffic to the `recommendation` service | Missing readiness probe on `consul` causes a startup race; frontend gets `connection refused` from Consul | Never queried NetworkPolicies (0 mentions in 45 tool calls). It reached the same wrong answer as problem 1: the frontend's `connection refused` errors at startup, logged in the ~1 s before Consul listens, are benign noise on every hotel-reservation deploy. Score 0/100 (the earlier smoke run of this problem scored 11/100). |
| 4 | `env_variable_shadowing_astronomy_shop` | `frontend-proxy` defines `FRONTEND_HOST` twice; the later `localhost` shadows `frontend`, so it routes to the wrong upstream while staying Running/Ready | `frontend-proxy` 65Mi memory limit too low; Envoy is OOMKilled in a crash loop | **⚠️ Invalid: environment bug.** On ARM64, Envoy really was OOMKilled at the upstream 65Mi limit. SREGym's `astronomy-shop-arm64.yaml` raises limits only for `product-catalog`/`checkout`. HolmesGPT correctly diagnosed a real crash loop (16 tool calls) but not the injected fault, which assumes the pod is Ready. Fixed locally (160Mi limit on ARM64); this problem will be rerun. |
| 5 | `mutating_webhook_resource_limits_social_network` | (rerun pending) | none: HolmesGPT crashed | **⚠️ Invalid: harness bug.** About 50 min into the run, an OpenRouter stream dropped mid-response (`peer closed connection without sending complete message body`). HolmesGPT exited without a result, and the driver fell back to submitting the raw CLI transcript as the diagnosis. Driver fixed: it now retries up to 3× within the agent budget and never submits stdout. Rerun pending. |
| 6 | `finalizer_deadlock_controller_hotel_reservation` | ConfigMap stuck Terminating with a finalizer; ClusterRole `configmap-cleanup-controller` was made read-only, so the controller logs 403s and can't remove it | `rate` Deployment's `RATE_BACKEND_QPS_LIMIT=500` "should be 5000" and throttles the backend | Never mentioned finalizers, ConfigMaps or RBAC in 62 tool calls. `500` is the chart default on every hotel-reservation deploy, so the "should be 5000" was invented. It again treated the baseline ~190 wrk2 socket timeouts per round (also in problem 1) as the incident. Score 0/100. |
| 7 | `kafka_poison_pill_hol_block` | Poison-pill record on topic `orders-fulfillment`: the consumer group can't deserialize it, never commits, and lag grows while pods stay Ready | **✅ Pass (78/100).** Malformed JSON record at offset 20 of `orders-fulfillment` halts `orders-validator` | Found it from consumer logs, which showed the last good commit at offset 20 and then the parse error at offset 20 (70 tool calls). It lost points for also listing the `jaeger` ExternalName Service as "Faulty Component #1": SREGym's own trace wiring, the same decoy as problem 2. `frontend-proxy` stayed Running with 0 restarts, which confirms the ARM64 memory fix. |
| 8 | `internal_traffic_policy_local_astronomy_shop` | `internalTrafficPolicy: Local` on `recommendation`, with caller and backend pinned to different worker nodes | not run | **⛔ Not runnable on this cluster.** SREGym's precondition fails: `requires at least two worker nodes`. `kind-sre-gym` is a single control-plane node, and SREGym's own kind config has 3 workers. Excluded from the pass rate. |
| 14 | `unschedulable_incorrect_port_assignment` | — | not run | **⏭️ Skipped** on request (listed in `skip.txt`), after problem 8 showed that single-node limits block some problems. Not verified whether it needs multiple nodes. Excluded from the pass rate. |
