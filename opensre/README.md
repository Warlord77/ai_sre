# OpenSRE — Evaluation

| | |
| --- | --- |
| **Source** | [Tracer-Cloud/opensre](https://github.com/Tracer-Cloud/opensre) |
| **Docs** | [opensre.com/docs](https://www.opensre.com/docs/) |
| **Integrations overview** | [opensre.com/docs/integrations-overview](https://www.opensre.com/docs/integrations-overview) |
| **Versions tested** | `2026.4.5` (curl), `2026.5.3` (homebrew) |
| **Date** | 2026-05-14 |

---

## 1. Why this evaluation

The market is consolidating around "AI SRE" agents — autonomous tools that triage pages, correlate metrics/logs/traces, draft RCAs, and (in some cases) take remediation actions. Commercial options are converging fast (Cleric, Resolve, Datadog Bits). The question this document answers:

**Is OpenSRE the open-source foothold to build on, or is it too early?**

Decision being made: adopt / pilot / defer / reject for the primary investigation agent across our multi-cloud estate. The decision is reversible, but onboarding cost and IAM surface make it expensive to repeat.

---

## 2. Outcomes — what the tool actually does

This tool is open-source and under Apache-2.0 license but still at an early stage. The platform promises to detect, fix, and create RCAs. Currently it lacks integrations with major industry-standard tools like PagerDuty, OpsGenie, Kubernetes etc. See [integrations overview](https://www.opensre.com/docs/integrations-overview).

### 2.1 Marketing ahead of shipped code

Docs site lists Helm as a GA integration and claims "60+ integrations." Installed CLI rejects `opensre integrations verify helm` and only ~30 services are registered.

### 2.2 The Helm bug — dual source of truth out of sync

Reproduced on `2026.4.5` and `2026.5.3`:

```bash
$ opensre integrations verify helm
Error: Invalid value: 'helm' is not one of [...]

$ opensre integrations verify | grep helm        # different code path
  helm   local store   failed   helm version --client failed (exit 1): Error: unknown flag: --client
```

Filed as [Tracer-Cloud/opensre#1973](https://github.com/Tracer-Cloud/opensre/issues/1973).

### 2.3 RCA only, no remediation

A thing for the future. Currently does not support any remediation.

---

## 3. Alternatives

| Tool | License | K8s breadth | Write actions | Maturity | Best when |
|---|---|---|---|---|---|
| **HolmesGPT** (Robusta) | Apache-2.0, CNCF Sandbox | Any cluster | ◐ via K8s Remediation MCP | Production-ready, 2.4 k★ | Open-source SRE agent, today |
| **k8sgpt** | Apache-2.0 | Single cluster | ✗ | GA, 7.8 k★ | Cluster linting / explain-only |
| **Cleric.ai** | Proprietary SaaS | ✓ | ✗ (read-only by design) | GA, Gartner Cool Vendor 2025 | Hands-off RCA at enterprise cost |
| **Resolve.ai** | Proprietary SaaS | ✓ | ✓ (PRs, kubectl, scripts) | GA, $1 B valuation 2025 | Autonomous remediation mandate |
| **Datadog Bits AI** | Bundled w/ DD | ◐ | ✗ | GA | All-in on Datadog already |

For an open-source path *today*, **HolmesGPT** is the closer-to-ready choice. For autonomous write actions, **Resolve.ai** is currently the only serious option.

---

## 4. Open Issue Filed By This Evaluation

Filed by this evaluation:

- [**#1973** — `opensre integrations verify helm` rejected as positional arg but accepted by no-arg path (Click Choice out of sync with registry)](https://github.com/Tracer-Cloud/opensre/issues/1973)

---

## 5. Decision

**Reject** — based on the evidence above.

---

## Appendix — references

**Code (read against `main` on 2026-05-14):**
- [`app/integrations/registry.py`](https://github.com/Tracer-Cloud/opensre/blob/main/app/integrations/registry.py)
- [`app/integrations/`](https://github.com/Tracer-Cloud/opensre/tree/main/app/integrations) — connectors
- [`app/cli/commands/integrations.py`](https://github.com/Tracer-Cloud/opensre/blob/main/app/cli/commands/integrations.py)
- [`app/cli/support/constants.py`](https://github.com/Tracer-Cloud/opensre/blob/main/app/cli/support/constants.py)
- [`app/tools/`](https://github.com/Tracer-Cloud/opensre/tree/main/app/tools) — agent tool surface
- [`app/agents/`](https://github.com/Tracer-Cloud/opensre/tree/main/app/agents) — investigation loop
- [`app/masking/`](https://github.com/Tracer-Cloud/opensre/tree/main/app/masking) · [`app/guardrails/`](https://github.com/Tracer-Cloud/opensre/tree/main/app/guardrails) · [`app/delivery/`](https://github.com/Tracer-Cloud/opensre/tree/main/app/delivery)

**PRs / issues quoted:**
- [PR #1657 — feat(integrations): add Helm CLI integration](https://github.com/Tracer-Cloud/opensre/pull/1657)
- [PR #1690 — docs(helm)](https://github.com/Tracer-Cloud/opensre/pull/1690)
- [Issue #321 — original Helm feature request](https://github.com/Tracer-Cloud/opensre/issues/321)

**External:**
- [k8sgpt-ai/k8sgpt](https://github.com/k8sgpt-ai/k8sgpt) · [robusta-dev/holmesgpt](https://github.com/robusta-dev/holmesgpt) · [cleric.ai](https://cleric.ai/)