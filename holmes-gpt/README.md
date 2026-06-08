# HolmesGPT — Evaluation


|                         |                          |
| ----------------------- | ------------------------ |
| **Author**              | `Biswa Prakash Mishra`   |
| **Date**                | `2026-05-18`             |
| **Time invested**       | `14 hours`               |
| **Tool version tested** | `0.30.0`                 |
| **Source / Docs**       | `https://holmesgpt.dev/` |
| **License**             | `Apache 2.0 License`     |
| **Category**            | `AI SRE agent`           |


---

## 1. What problem does this tool solve?

HolmesGPT is an AI based SRE agent to solve production incident across a range of infrastructure. k8s, VM, cloud services

---

## 2. How it works (architecture)

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

## Docker

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

## CLI

### Install Dependencies

```bash
sudo apt update
sudo apt install -y build-essential gcc python3-dev
```

### Install Pipx

```bash
sudo apt update
sudo apt install pipx
pipx ensurepath
```

### Install HolmesGPT

```bash
pipx install holmesgpt==0.30.0
```

if using python-3.14+ use this to disable Prometheus toolset [docs](https://github.com/HolmesGPT/holmesgpt/blob/master/CONTRIBUTING.md#prerequisites)

```bash
export DISABLE_PROMETHEUS_TOOLSET=true
```

## Setup Credentials

```bash
export OPENROUTER_API_KEY="<your-open-router-key-here>" 
export MODEL="openrouter/openai/gpt-5.4"
```

## To start

```bash
holmes ask "why is my service not starting"
```

restart your terminal to source your config file 

### Known setup gotchas

if using python-3.14+ use this to disable Prometheus toolset [docs](https://github.com/HolmesGPT/holmesgpt/blob/master/CONTRIBUTING.md#prerequisites)

```bash
export DISABLE_PROMETHEUS_TOOLSET=true
```

**OTEL Instrumentation is not available in CLI installation.**

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

*Prompt* : 

```
User: my nginx pod is pending. Please debug
```

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

Model Used: openai/gpt-5.4-nano, openai/gpt-5.4-mini, openai/gpt-5.4

Prompt Given to fix trhe problem:

```
A Solo Leveling themed web application has been deployed in the solo-leveling namespace, but the website is not accessible.

Investigate why the website is not accessible and fix the issue so that the Solo Leveling website is reachable at:
```

Outcome: There are 2 tasks to solve the challenge completely. The first was easy and could be solved by gpt-5.4-nano, gpt-5.4-mini and gpt-5.4, but the second challenge could be solved by gpt-5.4 after multiple trials (a trial is a fresh attempt from start)

---

### Scenario 3 (Easy): [Linux Debugging](https://labs.iximiuz.com/challenges/linux-debug-vanishing-worker-service) Problem

Model Used: openai/gpt-5.4

Prompt Given: 

```
A background worker.service has been deployed on this server. It's supposed to run continuously, picking up batches from a job queue.

But there's a problem - the service starts cleanly, prints a few heartbeat lines, then picks up a batch of work for processing and shortly afterwards silently crashes. systemd brings it back up again, but the job handling never advances beyond the first batch.

Your task: diagnose the root cause of the service's repeated death and find a way to make worker.service stay up and running for an extended period of time. Use sudo whenever possible to run commands. 
```

Outcome: The model was able to find the root cause and suggest possible fixes. The first suggested fix was applied and it solved the problem successfully. 

---

## 5. Demo


| Demo         | Link                                                                                 | Duration |
| ------------ | ------------------------------------------------------------------------------------ | -------- |
| `Scenario 3` | `https://drive.google.com/file/d/1jkU5qq7iJoTNGgcKhnqm4fs6deN0lAfi/view?usp=sharing` | `06:36`  |


---

## 6. Observations

- Some of the runs got stuck for a long time and had to be killed. 
- **Code quality:** Stable releases are often shipped weekly or biweekly. Rapid development/iteration. 
- **Community:** Slack, monthly zoom and community meetings and active github issues also. 
- **Documentation:** Mostly Complete. Some edge cases has to be addressed. 
- **Security posture:**  project explicitly discusses RBAC and controlled-access design
- **Performance:** TODO: Token consumption has to be analyzed for each run across tasks of different difficulty level. 
- **Stability:** Sometime it hanged. But root cause has to be idenified.

---

## 7. Comparison with alternatives

---

## 8. Pros

- Huge number of data integrations are available. 
- Advantage over general purpose agent like claude code is that, it integrates directly with a tool that don't have an native MCP. 
- Operator Mode (in development) will allow continuous autonomous monitoring. 
- Performs reasonably well using a weaker model like openai/gpt-5.4-nano for simple k8s tasks
- Read-Only Access - Respects RBAC permissions. All tool integrations guides comes with setting it up with correct RBAC permissions.  
- Can directly investigate alerts from alerting systems.  
- Support for custom runbooks.  This allows you to encode your debugging procedures so that HolmesGPT will execute that to debug

---

## 9. Cons

- It is still in CNCF sandbox project. 
- By design HolmesGPT never modifies your infrastructure. That is a safety feature, but it stops one step short of fixing your issues. Whereas a general purpose agent like codex on the same prompt will go ahead fix the issue unprompted. 
- Installation options are limited. Only via pipx, brew or cloning the repository to run. 
- Setup Documentation lacks complete details to run. e.g. if you run the application using python 3.14 or above you get an error and the fix to the error is in contribution docs.

---

## 10. Cost analysis

For a medium K8s problem in iximuiz labs the token usage is below. 


| Metric        | Tokens |
| ------------- | ------ |
| Input tokens  | ~1.01M |
| Output tokens | ~10K   |
| Total tokens  | ~1.1M  |


## TODO: The price per debugging session 

## 11. Verdict

**Defer**: Currently the tool in in development and there are rough edges. Very limited installation methods and all the installation methods are not complete (as in OTEL support is not there for CLI installation)

The most promising feature of holmes GPT is the operator mode. It allows it to run in background 24/7, notices if something is wrong, trigger an investigation and propose fixes. This feature is still in alpha and needs to be revisited. 

### Rationale

Currently HolmesGPT is in CNCF sandbox stage meaning its experimental in nature and has a lot of rough edges. The tool should be re-evaluated in 2-3 months. The primary thing in the re-evaluation should be 

1. what are the installation methods available and are those methods feature complete.
2. At what stage the operator mode is in. This is currently is alpha.

---

## 12. Issues / PRs filed


| Type            | Link                                                                                                     | Status |
| --------------- | -------------------------------------------------------------------------------------------------------- | ------ |
| Docs            | [https://github.com/HolmesGPT/holmesgpt/issues/2047](https://github.com/HolmesGPT/holmesgpt/issues/2047) | Closed |
| Enhancement/Bug | [https://github.com/HolmesGPT/holmesgpt/issues/2077](https://github.com/HolmesGPT/holmesgpt/issues/2077) | Closed |


---

