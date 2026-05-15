# <Tool Name> — PoC Evaluation

| | |
| --- | --- |
| **Author** | `<your-name>` |
| **Date** | `YYYY-MM-DD` |
| **Time invested** | `<X hours>` |
| **Tool version tested** | `<version>` |
| **Source / Docs** | `<links>` |
| **License** | `<license>` |
| **Category** | `<e.g. AI SRE agent / LLM gateway / observability / code assistant>` |

---

## 1. What problem does this tool solve?

One paragraph. What pain point does this address in our stack? Why are we evaluating it now?

---

## 2. How it works (architecture)

Explain the tool's internals — not marketing copy. Draw from source code, docs, or reverse-engineering.

- What's the core architecture? (agent loop, plugin system, API proxy, etc.)
- What LLM providers / models does it use? How?
- What data does it need access to? What permissions?
- Where does it run? (local CLI, sidecar, SaaS, self-hosted server)
- What does the deployment topology look like?

Include a diagram if it helps (Mermaid or ASCII is fine).

```
┌──────────┐      ┌───────────┐      ┌─────────┐
│  User    │─────▶│  Tool     │─────▶│  LLM    │
│          │◀─────│  (agent)  │◀─────│  API    │
└──────────┘      └─────┬─────┘      └─────────┘
                        │
                        ▼
               ┌────────────────┐
               │  Your infra    │
               │  (k8s/cloud/db)│
               └────────────────┘
```

---

## 3. Setup and reproduction steps

Everything needed for someone else on the team to reproduce this PoC from scratch. No "just install it" hand-waving.

### Prerequisites

- OS / runtime versions
- API keys / credentials needed
- Infrastructure dependencies (cluster, cloud account, etc.)

### Step-by-step

```bash
# Every command, in order, copy-pasteable
```

### Known setup gotchas

List anything that tripped you up or isn't in the official docs.

---

## 4. Scenarios tested

**Do not just test the happy path hello-world.** Test at least 3 scenarios that reflect real usage at one2n.

### Scenario 1: `<descriptive name>`

**What I did:**
```bash
# exact commands / config used
```

**What I expected:**

**What actually happened:**

**Evidence:** (screenshot, terminal output, or link to recording)

---

### Scenario 2: `<descriptive name>`

(same structure)

---

### Scenario 3: `<descriptive name — ideally a failure/edge case>`

(same structure)

---

## 5. Demo

Link to a short video (Loom, asciinema, or screen recording) showing the tool in action on a real-ish scenario. Not a hello-world.

| Demo | Link | Duration |
|------|------|----------|
| `<scenario>` | `<link>` | `<mm:ss>` |

If video isn't feasible, annotated screenshots with step-by-step narrative are acceptable.

---

## 6. Observations

What you noticed that isn't in the docs. Behaviour, quirks, quality signals.

- **Code quality:** Is the codebase well-structured? Tests? CI? Release cadence?
- **Community:** GitHub stars, contributors, issue response time, Discord/Slack activity.
- **Documentation:** Accurate? Complete? Or marketing-ahead-of-code?
- **Security posture:** What access does it need? Does it phone home? Data handling?
- **Performance:** Latency, resource usage, token consumption.
- **Stability:** Did it crash? Hang? Produce hallucinated output?

---

## 7. Comparison with alternatives

| Dimension | This tool | Alternative A | Alternative B |
|-----------|-----------|---------------|---------------|
| License | | | |
| Maturity (stars, age, release cadence) | | | |
| Solves our specific problem? | | | |
| Ease of setup | | | |
| Integrations we need | | | |
| Write actions / remediation | | | |
| Self-hosted option | | | |
| Cost (tokens, SaaS fee, infra) | | | |
| Active maintenance | | | |

Why did you pick these alternatives? What's the market landscape?

---

## 8. Pros

- (be specific — "it works" is not a pro)

---

## 9. Cons

- (be specific — "it's new" is not a con, explain the impact)

---

## 10. Cost analysis

- **Token/API costs:** What did this PoC cost to run? Extrapolate to production usage.
- **Infra costs:** What compute/storage does it need?
- **Human costs:** How much effort to set up, maintain, extend?

---

## 11. Verdict

Pick one: **Adopt** / **Pilot** (trial with a real team for X weeks) / **Defer** (revisit in X months) / **Reject**

### Rationale

2-3 sentences explaining the decision. Reference specific evidence from sections above.

### If Adopt/Pilot — next steps

- What would a pilot look like?
- Who owns it?
- What's the success criteria?
- Timeline?

### If Defer — revisit trigger

- What needs to change for us to re-evaluate? (feature shipped, maturity milestone, etc.)

### If Reject — what instead?

- What's the recommended alternative and why?

---

## 12. Issues / PRs filed

If you found bugs or gaps, file them upstream. Link them here. This builds our reputation in the community.

| Type | Link | Status |
|------|------|--------|
| Bug | `<link>` | Open |
| Feature request | `<link>` | Open |

---

## 13. References

- Links to source code you read
- Blog posts / talks that informed your evaluation
- Related internal docs or prior art

---

## Appendix: Raw notes / logs

<details>
<summary>Click to expand</summary>

Dump verbose logs, full command outputs, config files used, etc. here. Keeps the main doc clean but preserves evidence.

</details>
