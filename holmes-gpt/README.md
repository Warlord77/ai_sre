# HolmesGPT — Evaluation

| | |
| --- | --- |
| **Author** | `Biswa Prakash Mishra` |
| **Date** | `2026-05-18` |
| **Time invested** | `<X hours>` |
| **Tool version tested** | `0.30.0` |
| **Source / Docs** | `https://holmesgpt.dev/` |
| **License** | `Apache 2.0 License` |
| **Category** | `AI SRE agent` |

---

## 1. What problem does this tool solve?

HolmesGPT is an AI based SRE agent to solve production incident across a range of infrastructure. k8s, VM, cloud services

---

## 2. How it works (architecture)

Explain the tool's internals — not marketing copy. Draw from source code, docs, or reverse-engineering.

- What's the core architecture? (agent loop, plugin system, API proxy, etc.)
    - Agent Loop
    - 2 Orchestrators
        - Tool Calling LLM
        - IssueInvestigator

- What LLM providers / models does it use? How?
  - Can work with a wide range of [models/providers](https://holmesgpt.dev/latest/ai-providers/)
  - They [recommend](https://holmesgpt.dev/latest/installation/cli-installation/#quick-start) using Sonnet 4.0 or Sonnet 4.5 

- What data does it need access to? What permissions?
  - Multiple data sources [integration](https://holmesgpt.dev/latest/data-sources/)
  - Permissions are specific to data sources. Each intergration page has instructions. 

- Where does it run? (local CLI, sidecar, SaaS, self-hosted server)
  - Docker Container
  - Local CLI
  - K8s as a operator (in alpha at the moment of evaluation)

- What does the deployment topology look like?
  - Deployment topology would depend on the platform of deployment

---

## 3. Setup and reproduction steps

### Prerequisites

- An API key is required from the supported [providers](https://holmesgpt.dev/latest/ai-providers/)
- Docker 

### Step-by-step

Run the HolmesGPT container. An TUI will open and ask the user to give input. 

```bash
docker run -it --net=host \
-e OPENROUTER_API_KEY="<provider-key-here>" \
-e MODEL="<provider-model-here>" \
-v $HOME/.kube/config:/root/.kube/config us-central1-docker.pkg.dev/genuine-flight-317411/devel/holmes:0.30.0  \
ask 
```

If you want OTEL integration, Metrics, traces and logs will be exported to the specified otel endpoint. 

```bash
docker run -it --net=host \
-e OPENROUTER_API_KEY="<provider-key-here>" \
-e MODEL="<provider-model-here>" \
-e OTEL_EXPORTER_OTLP_ENDPOINT="<otel-endpoint-here>" \
-e OTEL_EXPORTER_OTLP_PROTOCOL="grpc" \
-e OTEL_SERVICE_NAME="holmesgpt" \
-v $HOME/.kube/config:/root/.kube/config us-central1-docker.pkg.dev/genuine-flight-317411/devel/holmes:0.30.0  \
ask 
```

### Known setup gotchas


---

## 4. Scenarios tested

### Scenario 1: (Easy): An nginx pod that is not schedulable due to mismatch of node selector

**What I did:**
```bash
cat > pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-pod
spec:
  containers:
    - name: nginx
      image: nginx:1.25
      ports:
        - containerPort: 80

  nodeSelector:
    disktype: ultra-ssd
```
```
laborant@dev-machine:~$ kubectl apply -f pod.yaml
```

**What I expected:**

Pod to remain in pending state 

**What actually happened:**

Pod remained in pending state

**Evidence:** (screenshot, terminal output, or link to recording)

The agent identified the root cause and suggested possible fixes. 

*Prompt* : User: my nginx pod is pending. Please debug

```
AI Response ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│                                                                                                                                               │
│                                                                                                                                               │
│                                                                   Findings                                                                    │
│                                                                                                                                               │
│   • Pod: default/nginx-pod                                                                                                                    │
│   • Status: Pending                                                                                                                           │
│   • Event: FailedScheduling                                                                                                                   │
│   • Reason (from event message): “0/3 nodes are available: 3 node(s) didn't match Pod's node affinity/selector.”                              │
│      • Also: “preemption: 0/3 nodes are available” (so rescheduling won’t be helped by preemption)                                            │
│                                                                                                                                               │
│                                                                                                                                               │
│                                                                  Root cause                                                                   │
│                                                                                                                                               │
│  nginx-pod has node affinity/selector constraints that match no nodes in your cluster (3/3 nodes don’t satisfy them), so the scheduler        │
│  cannot place it.                                                                                                                             │
│                                                                                                                                               │
│                                                                                                                                               │
│                                                                Fix (pick one)                                                                 │
│                                                                                                                                               │
│   1 Remove/relax node affinity/selector from the workload that created the pod (Deployment/Job/etc.).                                         │
│                                                                                                                                               │
│   • First, find the owning controller:                                                                                                        │
│                                                                                                                                               │
│      kubectl get pod nginx-pod -n default -o jsonpath='{.metadata.ownerReferences}'                                                           │
│                                                                                                                                               │
│   • Then edit/patch that controller to remove/change the spec.template.spec.affinity or spec.template.spec.nodeSelector.                      │
│                                                                                                                                               │
│   2 Add labels to nodes so they satisfy the selector/affinity.                                                                                │
│                                                                                                                                               │
│   • Check current node labels:                                                                                                                │
│                                                                                                                                               │
│      kubectl get nodes --show-labels                                                                                                          │
│                                                                                                                                               │
│   • Then update either:                                                                                                                       │
│      • the nodes (add matching labels), or                                                                                                    │
│      • the pod’s selector/affinity (make it target existing node labels)                                                                      │
│                                                                                                                                               │
│   3 If it’s using node taints via tolerations/affinity, ensure tolerations/affinity align.                                                    │
│                                                                                                                                               │
│   • Check node taints:                                                                                                                        │
│                                                                                                                                               │
│      kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.taints}{"\n"}{end}'                                         │
│                                                                                                                                               │
│                                                                                                                                               │
│                                                                                                                                               │
│                                                              Immediate next step                                                              │
│                                                                                                                                               │
│  Tell me which workload owns nginx-pod (output of the ownerReferences command above), and I’ll give the exact kubectl edit/patch to fix the   │
│  node affinity/selector.                                                                                                                      │
│                                                                                                                                               │
╰───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
```

---

### Scenario 2 (Hard): [K8s debugging](https://labs.iximiuz.com/challenges/troubleshoot-website-not-accessible-173199c4) from iximuiz labs 

In the iximuix labs dev environment a prompt was given
Model Used: openai/gpt-5.4-nano

Prompt Given to fix trhe problem:

```
A Solo Leveling themed web application has been deployed in the solo-leveling namespace, but the website is not accessible.

Investigate why the website is not accessible and fix the issue so that the Solo Leveling website is reachable at:
```

Outcome: It could successfully identify and fix the problem solving all the required tasks

---

### Scenario 3: Linux Debugging Problem

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

- Huge number of data integrations are available. 
- Advantage over general purpose agent like claude code is that, it integrates directly with a tool that don't have an native MCP like postgres. 
- Operator Mode (in development) will allow continuous autonomous monitoring. 
- Performs reasonably well using a weaker model like openai/gpt-5.4-nano for k8s tasks

---

## 9. Cons

- General purpose agents like claude code and 

---

## 10. Cost analysis

- **Token/API costs:** What did this PoC cost to run? Extrapolate to production usage.
- **Infra costs:** What compute/storage does it need?
- **Human costs:** How much effort to set up, maintain, extend?

---

## 11. Verdict

Pick one: **Adopt** / **Pilot** (trial with a real team for X weeks) / **Defer** (revisit in X months) / **Reject**

The most promising feature of holmes GPT is the operator mode. It allows it to run in background 24/7, notices if something is wrong, trigger an investigation and propose fixes. This feature is still in alpha and needs to be revisited. 

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

- Walkthrough docs in links in README rendered broken/un-styled pages. Filed an issue and this was fixed. 


| Type | Link | Status |
|------|------|--------|
| Docs | https://github.com/HolmesGPT/holmesgpt/issues/2047 | Closed |


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
