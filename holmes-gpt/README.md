# HolmesGPT — Combined Evaluation Report

| | |
| --- | --- |
| **Compiled from** | [Exp 1 — v0.30 on iximiuz Labs](exp1-iximiuz-v0.30/README.md) (Biswa Prakash Mishra) · [Exp 4 — v0.45 on the SRE Gym sandbox](exp4-sre-gym/README.md) (Sahil Joseph) · [Exp 5 — v0.45 on SREGym-Lite](exp5-sregym-lite/README.md) (Sahil Joseph) |
| **Date range** | `2026-05-18` → `2026-10-21` |
| **Time invested** | ~14 h (Exp 1) + ~5 h (Exp 4) + ~1 day (Exp 5) |
| **Tool versions tested** | `0.30.0`, `0.45.0` |
| **Source / Docs** | [holmesgpt.dev](https://holmesgpt.dev/) · [GitHub](https://github.com/HolmesGPT/holmesgpt) |
| **License** | `Apache 2.0` |
| **Category** | `AI SRE agent` (CNCF Sandbox) |

---

## TL;DR

| | Exp 1 (v0.30) | Exp 4 (v0.45) | Exp 5 (v0.45) |
|---|---|---|---|
| Test set | 3 iximiuz challenges (2 K8s, 1 Linux) | 3 alert-driven chaos scenarios on our own stack | SREGym-Lite: 17 independently graded K8s incidents |
| Data sources | K8s API only | K8s + Prometheus + Loki + Tempo + Alertmanager | K8s (filtered proxy) + Prometheus + Loki + Jaeger (MCP) |
| Who judged | Author | Author | SREGym LLM judge vs known root cause |
| Result | 2/3 correct, +1 partial | 2/3 correct (1 hedged), +1 partial | **1/7 valid problems passed (14%)**, avg judge score 19/100 |
| Verdict | Defer | Pilot | — (feeds this report) |

**Combined verdict: Defer.** HolmesGPT is a capable *log-and-metric reader*. When a fault leaves an explicit error
(a crash loop, a parse error at an offset, an admission rejection, a SIGTERM in Loki), it finds it quickly and
explains it well. On a graded benchmark where faults hide in configuration (NetworkPolicies, Service selectors,
RBAC, CronJobs, webhook mutations), it consistently anchored on the loudest unrelated error and confidently
reported the wrong root cause. That is not safe to put in front of an on-call engineer as a first answer.

---

## 1. What problem does this tool solve?

HolmesGPT is an open-source AI SRE agent that investigates production issues across Kubernetes, VMs and cloud
services. It runs an LLM tool-calling loop over read-only integrations (kubectl, Prometheus, Loki, Tempo,
Grafana, Helm, Alertmanager and 40+ others, plus any MCP server) and produces a root-cause analysis with suggested
fixes. It can be driven ad hoc (`holmes ask`), from alerts (`holmes investigate alertmanager`), or continuously
via an operator (alpha).

Across our three experiments the question narrowed from *"does it work?"* (Exp 1) to *"does more observability
make it better?"* (Exp 4) to *"how often is it actually right on incidents it hasn't seen?"* (Exp 5).

---

## 2. How it works (architecture)

```
alert / prompt ──► HolmesGPT agent loop (ToolCallingLLM / IssueInvestigator)
                     │   plan → call tool → read result → repeat (max-steps, default 100)
                     ├── kubernetes/core, kubernetes/logs, live-metrics, helm/core, bash
                     ├── prometheus/metrics, grafana/{loki,tempo,dashboards}
                     ├── MCP servers (SSE / streamable HTTP)  ← used for SREGym's Prom/Loki/Jaeger
                     └── runbooks / skills
                     │
                     ▼
                   LLM (LiteLLM: OpenAI, Anthropic, OpenRouter, Bedrock, …)
                     │
                     ▼
                   RCA text (CLI, JSON file, Slack)
```

- **Agent loop:** LLM-driven tool calls. Typical investigations made 16–70 tool calls in 1–4 minutes (Exp 5).
- **Models used:** `gpt-5.4`, `gpt-5.4-mini`, `gpt-5.4-nano` (Exp 1); `claude-sonnet-4-5` via OpenRouter (Exp 4, 5).
- **Access:** read-only by design. It never changes the cluster. RBAC `get/list/watch` is enough.
- **Deployment:** Docker image, pipx/brew CLI, or the K8s operator (alpha in v0.30, not re-tested).

---

## 3. Setup and reproduction

Each experiment's README has full steps:
- [Exp 1](exp1-iximiuz-v0.30/README.md#3-setup-and-reproduction-steps): Docker and pipx
- [Exp 4](exp4-sre-gym/README.md#3-setup-and-reproduction-steps): Docker + observability stack
- [Exp 5](exp5-sregym-lite/README.md#3-setup-and-reproduction): `make run-lite` against SREGym

### Consolidated setup gotchas

| # | Gotcha | Seen in | Impact | Fix |
|---|--------|---------|--------|-----|
| 1 | Python 3.14+ breaks the Prometheus toolset; the fix is only in CONTRIBUTING.md | Exp 1 | CLI won't start | `DISABLE_PROMETHEUS_TOOLSET=true` |
| 2 | OTEL instrumentation is Docker-only, not in the CLI install | Exp 1 | No self-telemetry from CLI | Use the Docker image |
| 3 | v0.45 disables Prometheus/Grafana toolsets by default; env vars no longer enable them, with no migration note | Exp 4 | Metrics/logs silently absent | Explicit `toolsets:` YAML ([issues #1](exp4-sre-gym/issues.md)) |
| 4 | `--net=host` (in all official Docker examples) doesn't reach host ports on macOS | Exp 4 | Container can't reach anything | Use `host.docker.internal` |
| 5 | Kubeconfig rewritten to `host.docker.internal` fails x509 SAN checks on kind | Exp 4 | `describe`/`get -o yaml` fail → wrong-image RCA missed | Use an endpoint whose cert carries that SAN (SREGym's proxy does) |
| 6 | `grafana/loki` / `grafana/tempo` need `grafana_datasource_uid` | Exp 4 | "Unable to connect" | Set the datasource UID |
| 7 | Intermittent `TypeError` in `prometheus.py:1869` drops ~30% of range queries | Exp 4 | Silent metric gaps | None (upstream) |
| 8 | `bash`/`kubectl` tool calls blocked by the approval prompt when piped | Exp 4 | Investigation stalls | `--no-interactive` |
| 9 | A dropped LLM stream (`incomplete chunked read`) kills the run with no result | Exp 5 | No answer at all | Retry wrapper (our driver retries 3×) |
| 10 | Requests up to 64K output tokens per call; fails with HTTP 402 when the remaining budget is below that | Exp 5 | Hard stop near a spend cap | Budget headroom or a lower max-tokens setting |
| 11 | Some runs hang and must be killed | Exp 1 | Wasted time | Wall-clock timeout around the CLI |

---

## 4. Scenarios tested (all experiments)

### 4.1 Hand-picked scenarios (Exp 1 and Exp 4)

| Exp | Scenario | Data available | Outcome |
|---|---|---|---|
| 1 | Pod unschedulable (nodeSelector mismatch) | K8s | ✅ Correct RCA + fixes |
| 1 | iximiuz "website not accessible" (2-part K8s) | K8s | ⚠️ Part 1 solved by all models; part 2 only `gpt-5.4`, after several fresh attempts |
| 1 | iximiuz Linux "vanishing worker service" | host shell | ✅ Correct RCA; first suggested fix worked |
| 4 | Redis scaled to 0 (`AppRedisDown`) | K8s + Prom + Loki | ✅ Correct, precise timeline from Prom + Loki SIGTERM |
| 4 | Postgres scaled to 0 (`AppPostgresDown`) | K8s + Prom + Loki | ✅ Correct but hedged (1 of 4 possibilities) |
| 4 | Backend image swapped to busybox (`AppPodCrashLooping`) | K8s + Prom + Loki | ⚠️ Traced the Redis/Postgres connection cascade, missed the wrong image (TLS blocked the spec read) |

### 4.2 SREGym-Lite benchmark (Exp 5)

10 of 17 problems attempted before the OpenRouter key hit its $10 limit. Full per-problem analysis:
[Exp 5 §5](exp5-sregym-lite/README.md#5-per-problem-observations).

| # | Problem | Fault lives in | HolmesGPT | Score |
|---|---------|----------------|-----------|------:|
| 1 | `cronjob_sidecar_blocks_completion_hotel_reservation` | CronJob sidecar never exits | ❌ blamed Consul readiness race | 0 |
| 2 | `edge_request_filter_cpu_saturation` | WAF regex on `frontend-proxy` | ❌ blamed otel→jaeger DNS | 0 |
| 3 | `network_policy_block` | NetworkPolicy deny-all | ❌ blamed Consul readiness race | 0 |
| 6 | `finalizer_deadlock_controller_hotel_reservation` | Read-only ClusterRole blocks finalizer | ❌ invented a "should be 5000" QPS limit | 0 |
| 7 | `kafka_poison_pill_hol_block` | Malformed Kafka record | ✅ found offset 20 parse error | 78 |
| 10 | `service_wrong_pod_selection_hotel_reservation` | Service selector too broad | ❌ same QPS story as #6 | 0 |
| 11 | `namespace_memory_limit` | ResourceQuota requires memory | ❌ near miss: right mechanism, blamed the symptom | 56 |
| 4, 5, 12 | — | — | ⚠️ invalid (environment/harness/credits), rerun pending | — |
| 8, 14 | — | — | ⛔ not runnable on 1 node / skipped | — |
| 9, 13, 15–17 | — | — | not yet run | — |

---

## 5. Demo

| Demo | Link | Duration |
|------|------|----------|
| Exp 1 — Linux vanishing worker service | [YouTube](https://youtu.be/f3oi8yChjQY?si=Wr3MvsIaF-e2mMHp) | 06:36 |
| Exp 5 — every investigation (raw answers) | [`results/answers/`](exp5-sregym-lite/results/answers/) | — |

---

## 6. Observations — what we learned across experiments

### Where HolmesGPT is good

- **Explicit-error faults.** It reliably finds faults that announce themselves: `FailedScheduling` events (Exp 1),
  a Redis SIGTERM in Loki correlated with a Prometheus replica drop (Exp 4), a Kafka consumer's parse error at a
  specific offset (Exp 5 #7), an admission rejection `must specify memory` (Exp 5 #11).
- **More observability helps, for those faults.** Exp 4 vs Exp 1: with Prometheus + Loki, timelines became precise
  to the second, and Loki covered pods that were already gone or unreachable via kubectl.
- **Graceful tool degradation.** When kubectl calls failed (TLS) or Prometheus queries errored, it switched to
  `kubernetes_jq_query` or Loki rather than giving up.
- **Fast and cheap per run.** 1–4 minutes per investigation and well under $1 of agent tokens on Sonnet 4.5.

### Where it fails

- **Anchoring on the loudest error.** In 5 of the 6 graded misses (all but #11) it built a coherent story around a
  real but unrelated signal. Hotel-reservation: brief Consul `connection refused` errors at startup (#1, #3) and
  the baseline wrk2 timeout count (#1, #6). Astronomy-shop: the `jaeger` ExternalName Service (#2, #7).
- **It doesn't enumerate where faults can hide.** Across 300+ tool calls in Exp 5 it never listed NetworkPolicies,
  CronJobs, RBAC, Service selectors/Endpoints, or admission webhooks unless an error pointed there. Configuration
  faults with quiet symptoms were invisible to it.
- **Confident fabrication.** In #6 it asserted a default setting "should be 5000" with no source, and reused the
  same invented story in #10. Every wrong answer read as confidently as the right ones.
- **Symptom over origin.** In #11 it found the right mechanism but named the affected Deployment as the faulty
  component and the ResourceQuota as merely "associated".
- **Hedging when blocked.** In Exp 4, when TLS blocked the StatefulSet spec read, it listed 4 possibilities
  instead of committing.

### Process and quality signals

- **Release cadence:** weekly or biweekly releases. v0.45 shipped breaking toolset-config changes without docs (gotcha 3).
- **Community:** CNCF Sandbox, active Slack, monthly community calls; our 2 upstream issues from Exp 1 were closed.
- **Documentation:** accurate for Linux and the happy path. macOS Docker, the v0.45 toolset format and Python 3.14
  are undocumented or buried.
- **Security posture:** read-only; never writes to the cluster. It sends cluster data (logs, specs, metrics) to the
  configured LLM provider. There is no anonymization, unlike K8sGPT's `--anonymize`.
- **Stability:** occasional hangs (Exp 1), one crash on a dropped LLM stream (Exp 5), and the Prometheus
  `TypeError` (Exp 4).

### Benchmark caveats (Exp 5)

Partial run (7 valid of 17). It used the SREGym `svelte` profile on a single-node, 8 GB kind cluster with one
model (`claude-sonnet-4-5`), and HolmesGPT got a generic prompt with no runbooks. SREGym notes that `svelte`
results aren't comparable with `full`-profile results. The direction is clear; the exact percentage isn't final.

---

## 7. Comparison with alternatives

Alternatives are the other tools evaluated in this repo, on their own write-ups.

| Dimension | HolmesGPT v0.45 | [K8sGPT 0.4.33](../k8sgpt/README.md) | [OpenSRE 0.1](../opensre/README.md) |
|-----------|-----------------|---------------|---------------|
| License | Apache 2.0 | Apache 2.0 | Apache 2.0 |
| Maturity | CNCF Sandbox, weekly releases | Mature OSS layout, Helm charts | Public alpha, ~7 releases/week |
| Approach | LLM agent loop explores freely | Fixed rule analyzers + LLM explanation | LLM agent over a few integrations |
| K8s API | ✅ Native | ✅ Analyzers | ❌ None (Helm only) |
| Prometheus / Loki / Tempo | ✅ Native + MCP | ❌ / partial | ❌ Grafana auth broken |
| Alert-driven RCA | ✅ Alertmanager | Operator → Slack/CloudEvents | ✅ single alert per run |
| Correct RCA in our tests | 2/3 · 2/3 · 1/7 graded | 0/2 (CLI) | 0/3 |
| Write actions / remediation | None (by design) | Operator mutations (got stuck) | None |
| Data minimization | None | ✅ Anonymization + explanation cache | — |
| Ease of setup | Medium (toolset YAML, macOS quirks) | Easy CLI, OpenRouter undocumented | Hard (many broken integrations) |
| Verdict | **Defer** (this report) | Reject | Defer |

**Takeaway:** HolmesGPT is clearly the strongest of the three: the only one that explores the cluster and
correlates metrics and logs. But "strongest of three" still means a 14% pass rate on graded, unseen incidents.

---

## 8. Pros

- **Broadest integrations.** 40+ toolsets plus arbitrary MCP servers. SREGym's Prometheus, Loki and Jaeger MCP servers plugged in with 10 lines of YAML.
- **Correlates metrics and logs into timelines.** It turned a Prometheus replica drop plus a Loki SIGTERM into a correct, timestamped RCA in about a minute (Exp 4).
- **Excellent on explicit errors.** Kafka poison pill (78/100), admission rejection, scheduling failures and crash loops.
- **Read-only and RBAC-friendly.** Safe to grant to an on-call bot.
- **Model-agnostic via LiteLLM.** Small models (`gpt-5.4-nano`) handled simple K8s cases (Exp 1).
- **Runbooks and skills.** Team procedures can be encoded. We didn't test this, and it's the most promising fix for the anchoring problem.

---

## 9. Cons

- **Wrong answers look like right answers.** No calibrated confidence. In Exp 5, 0/100 and 78/100 answers had the same assertive tone, so a responder can't tell which to trust.
- **Blind to quiet configuration faults.** NetworkPolicies, RBAC, selectors, CronJobs and webhooks were never inspected unless an error pointed there. These are common real-world causes.
- **Anchors on baseline noise.** Startup races and load-generator timeouts that exist on every healthy deploy were repeatedly reported as root causes.
- **No remediation.** It stops at the RCA by design. A general-purpose agent with write access goes on to fix it (noted in Exp 1).
- **Setup friction on macOS and Docker.** Gotchas 3–6 cost hours in Exp 4 and are undocumented.
- **Sends cluster data to the LLM with no anonymization.** It's a compliance question before any production use.
- **Fragile at the edges.** A dropped stream ends the run with no result, and a spend cap gives a hard 402.

---

## 10. Cost analysis

| Source | Measurement |
|---|---|
| Exp 1 | Medium iximiuz K8s problem: ~1.01M input + ~10K output tokens (~1.1M total) |
| Exp 4 | 16–30 tool calls, ~80–150K input tokens per incident, estimated **$0.40–0.75 per incident** on Sonnet 4.5 |
| Exp 5 | **$11.04** of OpenRouter spend for ~11 investigations, including retries and the SREGym judge (also Sonnet 4.5). About $1 per problem all-in; the agent's share is below that |

- **Infra:** none beyond a container. In Exp 5 it ran comfortably under `--memory 1g`.
- **Human:** about 5 hours of setup per new environment, mostly toolset config and networking. Per-incident time saved is about 10–15 minutes *when it's right* (Exp 4). In Exp 5 a wrong answer would have cost a responder time chasing the decoy.
- **Production extrapolation:** at ~$0.5–1 per alert, 50 alerts a day is roughly $750–1,500 a month on Sonnet 4.5. That's cheap if accuracy is high. At a 14% graded pass rate, most of that money buys confident wrong answers.

---

## 11. Verdict

**Defer.** Revisit in about 3 months, or sooner if the triggers below land.

### Rationale

Exp 1 and Exp 4 showed HolmesGPT working well on incidents with loud, explicit errors, and Exp 4 showed real
gains from observability integrations, which justified Exp 4's *Pilot*. Exp 5 tested it on independently graded
incidents it hadn't seen: 1 of 7 valid problems passed, the average score was 19/100, and the misses were
confident and plausible rather than "I don't know". For on-call use, a tool that is wrong about 85% of the time
on configuration faults, without signalling uncertainty, does more harm than good as a first responder.

### What would change the verdict (revisit triggers)

1. **SREGym-Lite pass rate ≥ 50%** on a full 17/17 run (`full` profile, multi-node cluster), with runbooks or a skill enabled.
2. **Calibrated confidence or explicit uncertainty** in the RCA output, so wrong answers are distinguishable.
3. **Systematic resource enumeration** (NetworkPolicies, RBAC, selectors, webhooks, Jobs), either built in or via a runbook that measurably fixes the anchoring.
4. Docs for the v0.45 toolset format and macOS Docker, and a fix for the Prometheus `TypeError`.
5. **Operator mode** out of alpha (the most promising feature in Exp 1).

### If we want to keep using it in the meantime

Use it as an **assistant, not an answer**: run it alongside a human on alerts that carry explicit errors (crash
loops, OOMs, failed schedules, consumer errors). There it's fast and usually right. Don't route
configuration-class incidents to it, and don't page on its RCA alone.

### Next experiment to run

Finish Exp 5: 8 runs remain (12, 13, 17, 5, 9, 15, 16, and the rerun of 4), roughly $10 of credit. Then repeat
the same suite with a **runbook or skill that forces enumerating NetworkPolicies, RBAC, Service selectors,
webhooks and CronJobs**. That isolates whether the gap is the agent's investigation strategy or the model.

---

## 12. Issues / PRs filed

| Type | Item | Source | Status |
|------|------|--------|--------|
| Docs | [holmesgpt#2047](https://github.com/HolmesGPT/holmesgpt/issues/2047) | Exp 1 | Closed |
| Enhancement/Bug | [holmesgpt#2077](https://github.com/HolmesGPT/holmesgpt/issues/2077) | Exp 1 | Closed |
| Bug/Docs | Toolsets disabled by default in v0.45, no migration note | Exp 4 [issues.md](exp4-sre-gym/issues.md) | Candidate to file |
| Docs | `--net=host` doesn't reach host ports on macOS Docker Desktop | Exp 4 | Candidate to file |
| Bug | Prometheus range-query `TypeError` (`prometheus.py:1869`) | Exp 4 | Candidate to file |
| Bug | Dropped LLM stream ends `holmes ask` with no result and no retry | Exp 5 | Candidate to file |
| Bug (SREGym) | ARM64: astronomy-shop `frontend-proxy` OOMKills at 65Mi; `astronomy-shop-arm64.yaml` doesn't raise it | Exp 5 | Candidate to file upstream (SREGym) |
| Bug (SREGym) | Aborted campaign leaves `mutating_webhook_resource_limits` webhooks installed; restart doesn't clean them | Exp 5 | Candidate to file upstream (SREGym) |

---

## 13. References

- Experiment write-ups: [Exp 1](exp1-iximiuz-v0.30/README.md) · [Exp 4](exp4-sre-gym/README.md) · [Exp 4 issues](exp4-sre-gym/issues.md) · [Exp 5](exp5-sregym-lite/README.md)
- Alternatives evaluated: [K8sGPT](../k8sgpt/README.md) · [OpenSRE](../opensre/README.md)
- [HolmesGPT docs — data sources](https://holmesgpt.dev/latest/data-sources/) · [AI providers](https://holmesgpt.dev/latest/ai-providers/)
- [SREGym-Lite](https://github.com/SREGym/SREGym/blob/main/docs/SREGym-Lite.md)
