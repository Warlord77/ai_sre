# Hodor PoC Evaluation

| | |
| --- | --- |
| **Author** | `Arvind` |
| **Date** | `2026-06-01` |
| **Time invested** | `8h` |
| **Tool version tested** | `v0.6.1` |
| **Source / Docs** | [github.com/mr-karan/hodor](https://github.com/mr-karan/hodor) · [MODELS.md](https://github.com/mr-karan/hodor/blob/main/docs/MODELS.md) |
| **License** | `MIT License` |
| **Category** | `AI Code Review Agent` |

---

## 1. What problem does this tool solve?

Manual code review is slow, inconsistent, and doesn't scale with team velocity. Linters and SAST tools catch predefined patterns but miss logic bugs that span multiple files, concurrency issues, and contract drift between services. Hodor fills this gap by acting as an **agentic code reviewer**: it autonomously explores a PR diff, cross-references related code, identifies production bugs, security issues, and logic errors, and produces a structured review with prioritised finding all without human supervision.

It works on GitHub PRs, GitLab MRs, Gitea/Forgejo PRs, and local git diffs, making it a platform-agnostic addition to CI or pre-push workflows.

---

## 2. How it works (architecture)

Hodor is a TypeScript CLI built on the [pi-coding-agent](https://github.com/badlogic/pi-mono) SDK. It receives a PR diff and autonomously explores the codebase using read-only tools to find bugs and logic errors, producing a structured review with prioritised findings.

```
PR URL / local diff
       │
       ▼
┌──────────────────────┐
│  Hodor CLI            │
│  (Commander.js)       │  ─  Parse URL/args, clone/checkout repo
└────────┬─────────────┘
         │
         ▼
┌────────────────────────────────────┐
│  pi-coding-agent session            │
│  • Read-only tools: bash, grep,    │
│    read, find                      │
│  • submit_review tool for output   │
│  • Priority levels P0–P3           │
│  • Diff embedding (<200 KB inline  │
│    >200 KB per-file on demand)     │
└────────┬───────────────────────────┘
         │
         ▼
┌──────────────────────┐     ┌──────────────────┐
│  pi-ai model layer   │◀───▶│  LLM (any        │
│  • Provider routing  │     │   provider:      │
│  • API key mgmt      │     │   Claude, GPT,   │
│  • Token tracking    │     │   Gemini, etc.)  │
└──────────────────────┘     └──────────────────┘
         │
         ▼
┌──────────────────────────────────────┐
│  Structured Review Output            │
│  { findings: [...],                  │
│    overall_correctness,              │
│    overall_explanation }             │
└──────────────────────────────────────┘
```

### Permissions

| Mode | Read access | Write access |
|------|-------------|--------------|
| Local | Working directory | None |
| GitHub PR | Public repo / `gh` CLI | `gh auth` + `--post` for comments |
| GitLab MR | Public repo / `glab` CLI | `glab auth` + `--post` |

### Deployment

No server component. Runs as a CLI process on: developer workstation (npx), CI pipeline (Docker image), or pre-push hook.

---

## 3. Setup and reproduction steps

### Prerequisites

- **Node.js >= 22** or **Bun**. `npx` auto-runs with Node
- **LLM API key**. One of: `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`, `OPENROUTER_API_KEY`
- **A local git repo** with a branch or uncommitted changes (for local mode)

### Step-by-step

```bash
# 1. Export your LLM API key
export GOOGLE_API_KEY=your-key    # (or OPENAI_API_KEY / ANTHROPIC_API_KEY / OPENROUTER_API_KEY)

# 2. Review a public PR
npx @mrkaran/hodor https://github.com/kubernetes/kubernetes/pull/137762 \
  --model google/gemini-2.5-pro-exp-03-25 -v

# 3. Or review local changes
npx @mrkaran/hodor --local --diff-against origin/main \
  --model google/gemini-2.5-pro-exp-03-25 -v
```

### Gotchas

- **Model format**: `provider/model-id` (e.g. `google/gemini-2.5-pro-exp-03-25`, `openrouter/anthropic/claude-sonnet-4-5-20250929`). Wrong slug = 400 error.
- **First npx run**: Downloads the package; subsequent runs use cache.
- **Large repos**: First-time PR review clones the repo, slow for big repos like Kubernetes. Local mode uses existing checkout.

---

## 4. Scenarios tested

**Approach:** All scenarios use real open-source PRs (no synthetic bug injection). Hodor runs in URL mode (autonomous clone + review) for public PRs, and local mode for branches in this repo. Quality is assessed against the criteria below rather than against seeded ground truth.

### Quality criteria

| Criteria | What to evaluate |
|----------|------------------|
| **Finding quality** | Are findings real production bugs or surface-level nits? |
| **Priority accuracy** | Are P0/P1/P2/P3 tags appropriate for each finding? |
| **Code location accuracy** | Are file paths and line ranges correct? |
| **Cross-file reasoning** | Does hodor connect related changes across files? |
| **Overall verdict** | Is `overall_correctness` consistent with the findings? |
| **False positives** | Are any findings clearly wrong or hallucinated? |

### Scenario 1: IaC — K8s gRPC probe TLS

**PR:** [kubernetes/kubernetes#137762](https://github.com/kubernetes/kubernetes/pull/137762)

**Stats:** 85 files, +1352 / -193 across kubelet, API, feature gate, validation, e2e tests.

```bash
npx @mrkaran/hodor https://github.com/kubernetes/kubernetes/pull/137762 \
  --model openrouter/anthropic/claude-opus-4.6 -v
```

**What I expected:**
- Hodor does not find any production issues since they are already peer reviewed.

**What actually happened:**
```
▶ Extracting review...
2026-06-02T11:00:42.571Z INFO  Captured 0 finding(s), verdict: patch is correct
2026-06-02T11:00:42.571Z INFO  Review complete (0 finding(s))

──────────────────────────────────────────────────
Tokens:  1.52M in (1.50M cached 99% · 20.8K fresh)  6.1K out  (1.60M total)
Agent:   43 turns  44 tool calls  3m 30s
Cost:    $1.4783
──────────────────────────────────────────────────
2026-06-02T11:00:42.571Z INFO  Cleaning up workspace...
2026-06-02T11:00:43.574Z INFO  Cleaned up workspace: /var/folders/c4/xhzwzdtj1pb90kj_72f9ct5w0000gn/T/hodor-review-0e1Qf2
✔ Review complete!
Review Complete

<!-- hodor-review -->
### Issues Found

No issues found.

### Summary
Total issues: 0 critical, 0 important, 0 minor.

### Overall Verdict
**Status**: Patch is correct

**Explanation**: The PR adds TLS support for gRPC container probes following standard Kubernetes patterns for feature-gated API fields. The implementation correctly handles: feature gate registration, field dropping when the gate is disabled, validation with gate awareness, backward compatibility for existing pods, unsafe.Pointer conversions between identical underlying types, and the kubelet prober TLS logic. The gRPC TLS approach (InsecureSkipVerify: true) is consistent with how HTTP probes handle TLS in pkg/probe/http/http.go. E2e tests properly cover success, failure, unhealthy response, and wrong port scenarios.
```

**Evidence:**
43 agent turns across 85 files. Traced the full contract from API types through validation, feature gate, kubelet prober, and e2e tests. Verified backward compatibility and generated file consistency.

---

### Scenario 2: CI/CD — Helm ShellCheck linting

**PR:** [helm/helm#31969](https://github.com/helm/helm/pull/31969)

**Stats:** 2 files, +50 / -13 covering a GitHub Actions workflow and a release script fix.

```bash
npx @mrkaran/hodor https://github.com/helm/helm/pull/31969 \
  --model openrouter/anthropic/claude-opus-4.6 -v
```

**What I expected:**
- Hodor identifies the issue with the wrong quotes being used

**What actually happened:**
```
▶ Extracting review...
2026-06-03T06:37:22.146Z INFO  Captured 1 finding(s), verdict: patch is incorrect
2026-06-03T06:37:22.146Z INFO  Review complete (1 finding(s))

──────────────────────────────────────────────────
Tokens:  30.5K in (26.9K cached 88% · 3.7K fresh)  3.6K out  (52.3K total)
Agent:   5 turns  5 tool calls  1m 15s
Cost:    $0.2354
──────────────────────────────────────────────────
2026-06-03T06:37:22.146Z INFO  Cleaning up workspace...
2026-06-03T06:37:22.248Z INFO  Cleaned up workspace: /var/folders/c4/xhzwzdtj1pb90kj_72f9ct5w0000gn/T/hodor-review-DOytTn
✔ Review complete!
Review Complete

<!-- hodor-review -->
### Issues Found

**Critical (P0/P1)**
- **[P0] Literal quotes in heredoc break download URLs in release notes** (`scripts/release-notes.sh:84-89`)
  - Inside a `cat <<EOF` heredoc (lines 62–109), double quotes are not shell quoting — they are literal characters in the output. The change from `helm-${RELEASE}-darwin-amd64.tar.gz` to `helm-"${RELEASE}"-darwin-amd64.tar.gz` inserts literal `"` characters into the generated URLs, producing broken links like `https://get.helm.sh/helm-"v3.1.0"-darwin-amd64.tar.gz`. This affects all six modified platform lines (MacOS amd64/arm64, Linux amd64/arm/arm64/i386). The original `${RELEASE}` without quotes was correct inside the heredoc — variable expansion happens automatically and word splitting does not apply in heredocs. The `$()` command substitutions (the `cat` calls) are unaffected since quotes inside `$()` are processed as normal shell syntax.

### Summary
Total issues: 1 critical, 0 important, 0 minor.

### Overall Verdict
**Status**: Patch has blocking issues

**Explanation**: The PR incorrectly adds double quotes around `${RELEASE}` inside a heredoc (`cat <<EOF`), where quotes are literal output characters, not shell quoting. This produces broken download URLs with literal quote characters in the release notes for six platform entries. The original unquoted `${RELEASE}` was already correct inside the heredoc since word splitting does not apply there.
```

**Evidence:**
5 turns to find a P0 bug. Spotted that double quotes inside a heredoc are literal characters, not shell quoting. Would have broken all download URLs in the release notes.

---

### Scenario 3: Security — External Secrets RBAC hardening

**PR:** [external-secrets/external-secrets#6295](https://github.com/external-secrets/external-secrets/pull/6295)

**Stats:** 6 files, +89 / -1 covering Helm chart, RBAC templates, and conditional logic.

```bash
npx @mrkaran/hodor https://github.com/external-secrets/external-secrets/pull/6295 \
  --model openrouter/openai/gpt-5.4 -v
```

**What I expected:**
- Hodor understands the privilege escalation chain (SA compromise → token creation → cluster-admin impersonation)
- Hodor does not find any issues

**What actually happened:**
```
▶ Extracting review...
2026-06-03T07:14:53.169Z INFO  Captured 0 finding(s), verdict: patch is correct
2026-06-03T07:14:53.169Z INFO  Review complete (0 finding(s))

──────────────────────────────────────────────────
Tokens:  84.6K in (69.9K cached 83% · 14.7K fresh)  9.3K out  (94.0K total)
Agent:   10 turns  14 tool calls  3m 24s
Cost:    $0.1941
──────────────────────────────────────────────────
2026-06-03T07:14:53.169Z INFO  Cleaning up workspace...
2026-06-03T07:14:53.258Z INFO  Cleaned up workspace: /var/folders/c4/xhzwzdtj1pb90kj_72f9ct5w0000gn/T/hodor-review-HH4Q45
✔ Review complete!
Review Complete

<!-- hodor-review -->
### Issues Found

No issues found.

### Summary
Total issues: 0 critical, 0 important, 0 minor.

### Overall Verdict
**Status**: Patch is correct

**Explanation**: The chart change cleanly gates the `serviceaccounts/token` RBAC rule behind a new boolean value, and the default remains unchanged. The new value is wired through the template, schema, defaults, and unit tests without introducing a production-impacting regression in the diff shown.
```

**Evidence:**
10 turns evaluating the privilege escalation chain. Confirmed the RBAC gating logic is sound, defaults are safe, and no regression is introduced.

---

### Scenario 4: Bug fix — K8s job controller active=0

**PR:** [kubernetes/kubernetes#139457](https://github.com/kubernetes/kubernetes/pull/139457)

**Stats:** 2 files, +40 / -2 covering the job controller pod creation backoff path.

```bash
npx @mrkaran/hodor https://github.com/kubernetes/kubernetes/pull/139457 \
  --model openrouter/openai/gpt-5.4 -v
```

**What I expected:**
- Hodor identifies the root cause: hardcoded `active=0` when pod creation is deferred during backoff
- The fix correctness is evaluated: does it properly reflect the true active pod count?
- Edge cases are considered (e.g., all pods in backoff, mixed backoff/running states)

**What actually happened:**
```
▶ Extracting review...
2026-06-03T10:25:02.643Z INFO  Captured 0 finding(s), verdict: patch is correct
2026-06-03T10:25:02.643Z INFO  Review complete (0 finding(s))

──────────────────────────────────────────────────
Tokens:  151.0K in (124.7K cached 83% · 26.3K fresh)  4.0K out  (155.0K total)
Agent:   9 turns  20 tool calls  1m 20s
Cost:    $0.1574
──────────────────────────────────────────────────
2026-06-03T10:25:02.644Z INFO  Cleaning up workspace...
2026-06-03T10:25:03.607Z INFO  Cleaned up workspace: /var/folders/c4/xhzwzdtj1pb90kj_72f9ct5w0000gn/T/hodor-review-d5XtV9
✔ Review complete!
Review Complete

<!-- hodor-review -->
### Issues Found

No issues found.

### Summary
Total issues: 0 critical, 0 important, 0 minor.

### Overall Verdict
**Status**: Patch is correct

**Explanation**: The logic change is consistent with how `active` is computed and consumed later in status updates: on a pod-creation backoff, no create/delete occurs, so preserving the current active count avoids the invalid `Ready > Active` status without altering reconciliation behavior. I did not find any new production bug introduced by the diff.
```

**Evidence:**
9 turns, 20 tool calls. Traced the active-count logic through the job controller's reconciliation loop and confirmed the fix doesn't introduce new edge cases.

---

### Scenario summary table

| # | Scenario | Type | Diff size | Files | Findings | Correctness |
|---|----------|------|-----------|-------|----------|-------------|
| 1 | K8s gRPC probe TLS | IaC | +1352 / -193 | 85 | 0 | patch is correct |
| 2 | Helm ShellCheck linting | CI/CD | +50 / -13 | 2 | 1 | patch is incorrect |
| 3 | External Secrets RBAC | Security | +89 / -1 | 6 | 0 | patch is correct |
| 4 | K8s job controller active=0 | Bug fix | +40 / -2 | 2 | 0 | patch is correct |

---

## 5. Demo

| Demo | Link | Duration |
|------|------|----------|
| `<scenario>` | `<link>` | `<mm:ss>` |

---

## 6. Observations

- **Code quality**: Well-structured TypeScript, TypeBox schema validation, good test coverage.
- **Community**: 105 stars, 1 contributor (mr-karan), 4 releases. A small project with no community channels.
- **Documentation**: Thorough README + dedicated docs for models, skills, automated reviews.
- **Security**: Agent is read-only. API keys via env vars only. One surface worth noting: `.agents/skills/` files in the reviewed repo could influence agent behaviour (though they're markdown guidelines, not executable code).
- **Performance**: Small diffs are near-instant; large diffs scale with file count. Token usage varies by model and diff size.
- **Stability**: No crashes. Handles edge cases (empty findings, missing keys, invalid API keys) gracefully.

---

## 7. Comparison with alternatives

| Dimension | Hodor | GitHub Code Review (built-in) | CodeRabbit | Claude Code (manual prompt) |
|-----------|-------|-------------------------------|------------|----------------------------|
| **Self-hosted** | Yes (Docker + CLI) | No | No | Yes (CLI) |
| **Agentic (autonomous tool use)** | Yes (bash, grep, read) | No (suggestion lines only) | Limited (file reader) | Yes (if scripted) |
| **Structured output** | JSON findings + priorities | Inline comments | Inline comments | Free text |
| **Cost model** | Token cost only | Free | Per-seat SaaS | Token cost only |

---

## 8. Pros

- Genuinely agentic. The model explores the codebase autonomously, not just a prompt-template wrapper around a diff.
- Structured JSON output with prioritised findings validates against a schema. Easy to parse, store, and integrate.
- Works offline with `--local`. No GitHub/GitLab account needed for pre-push or internal reviews.
- LLM-agnostic. Supports any provider pi-ai routes (Anthropic, OpenAI, OpenRouter, Bedrock, Gemini, Mistral, xAI, Groq).
- Prompt steering works. `--prompt` allows domain-specific review focus.
- Token optimisation via diff embedding and incremental reviews is well thought out.

---

## 9. Cons

- Single-purpose. Only does code review and cannot remediate issues, apply patches, or create fix PRs.
- Depends on `gh`/`glab` CLI tools for PR comment posting. An extra credential management step.
- No built-in RBAC or approval workflow. If `--post` is enabled in CI, anyone who triggers the CI can post a review comment.
- Agent quality depends entirely on the underlying model. A weak model returns weak reviews.
- Skills injection surface: `.agents/skills/` files in the reviewed repo could influence the agent's behaviour (though they are markdown guidelines, not executable code).
- Incremental review requires a prior hodor comment on the PR. First-run always does a full review.

---

## 10. Cost analysis

| Scenario | Model | Tokens (in/out) | Turns | Tool calls | Time | Cost |
|----------|-------|-----------------|-------|------------|------|------|
| S1 K8s gRPC probe TLS | claude-opus-4.6 | 1.52M / 6.1K | 43 | 44 | 3m 30s | $1.4783 |
| S2 Helm ShellCheck linting | claude-opus-4.6 | 30.5K / 3.6K | 5 | 5 | 1m 15s | $0.2354 |
| S3 External Secrets RBAC | gpt-5.4 | 84.6K / 9.3K | 10 | 14 | 3m 24s | $0.1941 |
| S4 K8s job controller | gpt-5.4 | 151.0K / 4.0K | 9 | 20 | 1m 20s | $0.1574 |
| **Total** | | | | | | **$2.0652** |

Costs are driven by two factors: **repo size** (cloning kubernetes/kubernetes for S1 added clone time and diff size) and **agent turns** (more turns = more tokens). Small diffs on smaller repos (S2–S4) cost under $0.25 each.

**How caching reduces costs:** The LLM provider caches repeated prompt prefixes (system prompt, tools, diff metadata) across agent turns within a session. S1 hit 99% cache (1.50M cached, 20.8K fresh). Without caching the 43-turn run would have cost much more. This is provider-side, ephemeral (5–10 min TTL), and happens automatically.

---

## 11. Verdict

**Pilot**: trial with a real team for 2–4 weeks

### Rationale

Hodor found a real P0 bug in the wild (heredoc quoting in Helm release script) and produced zero false positives across all 4 scenarios. The tool is genuinely agentic: it explores code across file boundaries and produces structured, prioritised findings. Cost is negligible ($0.16–$1.48 per PR, averaging ~$0.50). A pilot is needed to validate model choice (Opus 4.6 was more thorough than GPT-5.4 in this test), team integration, and whether the findings lead to action.

### Next steps

- Pick a real team repo and run Hodor on 10–20 open PRs
- Decide which provider/model to standardise on (Opus for depth, GPT-5.4/Gemini for speed and cost)
- Integrate into CI as a non-blocking reviewer. Post findings as comments, don't gate merges
- Evaluate after 2 weeks: is it catching things the team misses? Are the findings actionable? Is the cost acceptable?

---

## 12. Issues / PRs filed

| Type | Link | Status |
|------|------|--------|
| Bug | `<link>` | Open |

---

## 13. References

- [Hodor GitHub repo](https://github.com/mr-karan/hodor). Source code, docs, and Docker image.
- [pi-coding-agent SDK](https://github.com/badlogic/pi-mono). The agent runtime Hodor builds on.


