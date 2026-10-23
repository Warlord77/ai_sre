# HolmesGPT — SREGym-Lite on a VM with gpt-oss-120b

| | |
| --- | --- |
| **Author** | `Sahil Joseph` |
| **Date** | `2026-10-23` |
| **Tool version tested** | HolmesGPT `0.45.0` (Docker image) |
| **Benchmark** | [SREGym-Lite](https://github.com/SREGym/SREGym/blob/main/docs/SREGym-Lite.md), 17 problems |
| **Model (agent and judge)** | `gpt-oss-120b` on the one2n GPUStack (vLLM 0.25.1) |
| **Cluster** | SREGym's upstream kind setup (1 control plane + 3 workers, Calico), 16 GB, `--profile full` |
| **Setup** | [setup.md](setup.md) |
| **Builds on** | [Experiment 3: HolmesGPT on SREGym-Lite](../3-sregym-lite/README.md) (Sonnet 4.5, single-node, `svelte`) |

---

## 1. What this answers

Experiment 3 ran HolmesGPT on SREGym-Lite with Claude Sonnet 4.5 on a single-node, 8 GB cluster, and
only 7 problems produced valid grades. This run repeats the full suite on SREGym's own 4-node kind
setup with the `full` profile, using a self-hosted open-weight model (`gpt-oss-120b`) instead of a
commercial API. The question: how does HolmesGPT score with a self-hosted model on the complete,
upstream-comparable benchmark?

Only the **diagnosis** stage is run: HolmesGPT is read-only, so mitigation would fail by construction.

---

## 2. Method

- Problems run one at a time (`make run-one PROBLEM=<id>`), in SREGym-Lite order.
- HolmesGPT gets the application name, namespace(s) and description from SREGym, and must end with a
  `ROOT CAUSE` section. It isn't told the fault type. Up to 60 steps, 3 attempts on a failed run,
  within SREGym's 30-minute agent budget.
- Data sources: Kubernetes through SREGym's filtered proxy, plus SREGym's Prometheus, Loki and Jaeger MCP servers.
- SREGym's LLM judge scores the diagnosis against the known root cause (pass/fail and a 0–100 composite).
- The same model is agent and judge, which can flatter the agent; the judge uses a fixed checklist rubric.

---

## 3. Results

### Scorecard

| Problems run | ✅ Passed | ❌ Failed | ⚠️ Not graded | Pass rate | Avg judge score | Avg investigation |
|---:|---:|---:|---:|---:|---:|---:|
| 2/17 | 0 | 2 | 0 | 0% | 6/100 | 4.8 min |

### Per problem

| # | Problem | Diagnosis | Score | Investigation | Notes |
|---|---------|-----------|------:|--------------:|-------|
| 1 | `cronjob_sidecar_blocks_completion_hotel_reservation` | ❌ fail | 0 | 3.4 min | Verdict False (composite 0.00). D1 0.00, D2 0.00, D3 0.00. 21 tool calls, 22 LLM calls, 518K tokens |
| 2 | `edge_request_filter_cpu_saturation` | running | | | |
| 3 | `network_policy_block` | ❌ fail (deploy noise amplified by OpenEBS incident) | 11 | 6.3 min | Verdict False (composite 0.11). D1 0.00, D2 0.00, D3 0.33. 17 tool calls, 18 LLM calls, 459K tokens |
| 4 | `env_variable_shadowing_astronomy_shop` | pending | | | |
| 5 | `mutating_webhook_resource_limits_social_network` | pending | | | |
| 6 | `finalizer_deadlock_controller_hotel_reservation` | pending | | | |
| 7 | `kafka_poison_pill_hol_block` | pending | | | |
| 8 | `internal_traffic_policy_local_astronomy_shop` | pending | | | |
| 9 | `service_dns_resolution_failure_social_network` | pending | | | |
| 10 | `service_wrong_pod_selection_hotel_reservation` | pending | | | |
| 11 | `namespace_memory_limit` | pending | | | |
| 12 | `valkey_auth_disruption` | pending | | | |
| 13 | `secret_rotation_stale_env_credentials_astronomy_shop` | pending | | | |
| 14 | `unschedulable_incorrect_port_assignment` | pending | | | |
| 15 | `duplicate_pvc_mounts_social_network` | pending | | | |
| 16 | `rolling_update_misconfigured_social_network` | pending | | | |
| 17 | `search_rate_retry_collapse_hotel_reservation` | pending | | | |

---

## 4. Per-problem observations

Ground truth, what HolmesGPT concluded, and how it got there. Added after each problem finishes.

| # | Problem | Ground truth | What HolmesGPT concluded | Why it passed / missed |
|---|---------|--------------|--------------------------|------------------------|
| 1 | `cronjob_sidecar_blocks_completion_hotel_reservation` | CronJob `audit-log-archiver`: a sidecar keeps the Job pod from completing | Six services crash at startup with `panic: no reachable servers` because their MongoDB pods are created after them (e.g. `mongodb-geo` 05:12:39 vs `geo` 05:11:10); fix with init containers or startup probes | Never listed CronJobs or Jobs (0 of 21 tool calls). It read pods, events and 12 sets of pod logs, found the startup crashes, and stopped. That startup race happens on **every** hotel-reservation deploy and has cleared by the time the fault is injected, so it is baseline noise. Experiment 3 (Sonnet 4.5) also missed this problem, anchoring on the equivalent Consul startup errors. One tool call came back named `kubernetes_tabular_query<\|channel\|>commentary`: gpt-oss's harmony channel marker leaked into the tool name, so the call matched no tool. |
| 3 | `network_policy_block` | NetworkPolicy `deny-all-recommendation` blocks all traffic to the `recommendation` service | Six services crash-looped with `panic: no reachable servers` because their MongoDB pods started late, after slow PVC provisioning | Never queried NetworkPolicies (17 tool calls: pods, logs, events, jq queries). The OpenEBS stall (run note 2) made the startup crashes louder than usual (restart counts up to 7, late `ProvisioningSucceeded` events). Problem 1 later showed the same decoy and the same answer on a clean deploy, so this counts as a real miss. Experiment 3 scored 0 here with the same blind spot. |

---

## 5. Run notes

Issues hit while running, in order.

1. **First deploy timed out on cold downloads.** The first `network_policy_block` attempt never reached
   HolmesGPT. Deploy attempts 1 and 2 failed because a Helm dependency (`prometheus-node-exporter-4.23.2.tgz`
   from GitHub release assets) timed out. Attempt 3 got past that, but SREGym's in-cluster `mcp-server`
   didn't become ready within its 180 s rollout timeout: pulling `ghcr.io/sregym/sregym-mcp:latest`
   (300 MB) took 3m19s on a fresh node. Fix: pre-pulled that image on all four nodes
   (`docker exec <node> crictl pull ...`) and set `WAIT_FOR_POD_READY_TIMEOUT=1800`. Not counted as a run.
2. **MongoDB pods stuck Pending (OpenEBS).** On the second `network_policy_block` deploy, 4 of 6
   hotel-reservation MongoDB PVCs never bound, so `mongodb-{profile,recommendation,reservation,user}`
   stayed Pending and their services crash-looped. The OpenEBS local-PV provisioner lost its leader
   lease at 04:40:51 (API reads were timing out during the deploy) and restarted mid-provision. It left
   its finished `init-pvc-*` helper pods behind, and every retry failed with
   `pods "init-pvc-…" already exists`. Fix: deleted the stale helpers, restarted the provisioner, and
   restarted the two crash-looping services. All 19 pods were Ready at 04:57:35. SREGym was still waiting
   for readiness (thanks to the 1800 s timeout) and injected the fault at 04:57:37, so the run is valid.
   [`scripts/openebs-watchdog.sh`](scripts/openebs-watchdog.sh) now runs alongside the benchmark and
   applies the same fix automatically.
