# HolmesGPT Issues

Issues and gotchas encountered running HolmesGPT v0.45.0 (Docker) against the local
SRE Gym kind cluster. Format mirrors [`../opensre/issues.md`](../opensre/issues.md).

---

## 1. Built-in toolsets disabled by default (no migration note)

**Status:** Workaround available
**Command affected:** `holmes investigate`, `holmes ask`, `holmes toolset list`

### Symptom

`prometheus/metrics`, `grafana/loki`, `grafana/tempo`, and `grafana/dashboards` report as
`disabled` in `holmes toolset list` even with `PROMETHEUS_URL`, `GRAFANA_URL`, and
`GRAFANA_API_KEY` set as environment variables. The agent silently runs without metrics or
log access and produces K8s-only RCA.

### Root Cause

In v0.45 built-in toolsets are disabled by default and no longer auto-enable from environment
variables. v0.30 auto-enabled them when the corresponding env var was present. There is no
migration note documenting this breaking change.

### Fix

Explicitly enable each toolset in `~/.holmes/config.yaml` (mounted to
`/root/.holmes/config.yaml` in the container), using `enabled: true` plus a nested `config:`
block:

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
      grafana_datasource_uid: "loki"
```

---

## 2. `--net=host` does not reach host ports on macOS Docker Desktop

**Status:** Workaround available
**Command affected:** all Docker-based `holmes` invocations

### Symptom

Every integration using `localhost` (`http://localhost:9090`, `:3000`, `:9093`) fails to
connect from inside the container, despite the official HolmesGPT Docker examples using
`--net=host`. Prometheus/Grafana/Alertmanager toolsets report "Unable to connect".

### Root Cause

On macOS, Docker containers run inside a Linux VM. `--net=host` binds to the VM's network
namespace, not the Mac host's. Port-forwarded services on the Mac (`localhost:9090` etc.) are
not reachable from the VM via `localhost`.

### Fix

Replace `localhost` with `host.docker.internal` in all service URLs (`holmes-config.yaml` and
`--alertmanager-url`):

```yaml
prometheus_url: "http://host.docker.internal:9090"
```

```bash
holmes investigate alertmanager --alertmanager-url http://host.docker.internal:9093
```

---

## 3. K8s API server unreachable from container (kind kubeconfig)

**Status:** Workaround available
**Command affected:** all `kubernetes/*` toolsets

### Symptom

```
dial tcp 127.0.0.1:51268: connect: connection refused
```

The kind kubeconfig points the API server at `https://127.0.0.1:<port>`, which resolves to the
container's own loopback inside Docker, not the kind control-plane on the Mac.

### Root Cause

Same macOS Docker VM networking as issue 2 — `127.0.0.1` in the mounted kubeconfig is the
container loopback.

### Fix

Patch the kubeconfig to use `host.docker.internal` and mount the patched file:

```bash
kubectl config view --context kind-sre-gym --minify --raw \
  | sed 's|https://127.0.0.1:|https://host.docker.internal:|g' \
  > /tmp/kube-docker.yaml
```

```
-v /tmp/kube-docker.yaml:/root/.kube/config
```

---

## 4. TLS x509 errors after kubeconfig patch (cert SAN mismatch)

**Status:** No fix — degrades K8s investigation
**Command affected:** `kubectl describe`, `kubectl get -o yaml`, `kubectl top` inside container

### Symptom

```
x509: certificate is valid for localhost, sre-gym-control-plane, kubernetes, ...,
not host.docker.internal
```

`kubernetes_describe` and pod-spec reads fail. In the backend-crashloop scenario the agent could
not inspect the deployment spec and therefore **missed the wrong container image** as the root
cause.

### Root Cause

The kind API server certificate is issued with SANs for `localhost` and
`sre-gym-control-plane`, not `host.docker.internal`. Once the kubeconfig server address is
rewritten (issue 3), TLS verification of the API server fails for operations that go through
the Go kubectl client.

### Fix

No clean fix applied in this run. Options for a future run:
- Add `host.docker.internal` as an extra SAN to the kind cluster certificate via
  `kubeadmConfigPatches` (`apiServer.certSANs`) in `kind-cluster.yaml`, then recreate the cluster.
- Add a `127.0.0.1 host.docker.internal` entry to the container's `/etc/hosts` and leave the
  kubeconfig server at `127.0.0.1` with `--net=host` (Linux hosts only).
- Run against a real GKE/EKS cluster where this macOS-specific issue does not arise.

The agent partially compensates by using `kubernetes_jq_query` (raw API JSON) and Loki, but
these do not expose the `spec.template.spec.containers[].image` field clearly enough for the
LLM to catch an image swap.

---

## 5. `grafana/loki` and `grafana/tempo` fail without datasource UID

**Status:** Fixed (config)
**Command affected:** `grafana_loki_query`, `grafana_tempo_query`

### Symptom

```
Unable to connect to Loki / Tempo
```

even with a valid `api_url` and `api_key` pointing at Grafana.

### Root Cause

These toolsets query Loki/Tempo **through** Grafana's datasource proxy, not directly. Without
`grafana_datasource_uid` the toolset treats `api_url` as a direct Loki/Tempo endpoint and the
request 404s inside Grafana.

### Fix

Add the datasource UID (visible in Grafana → Connections → Data sources → URL) to each toolset
config:

```yaml
grafana/loki:
  config:
    grafana_datasource_uid: "loki"
grafana/tempo:
  config:
    grafana_datasource_uid: "tempo"
```

---

## 6. Prometheus range query `TypeError` drops results intermittently

**Status:** No fix — upstream bug
**Command affected:** `prometheus/metrics` range queries

### Symptom

```
TypeError: '>' not supported between instances of 'NoneType' and 'int'
  at prometheus.py:1869
```

Roughly 30% of range queries return empty results instead of data. No error is surfaced to the
LLM — the tool just returns nothing.

### Root Cause

A null value in the range-query response path is compared against an int without a guard in
HolmesGPT v0.45's `prometheus/metrics` toolset (`prometheus.py:1869`).

### Fix

No upstream fix as of v0.45. The agent recovers by re-issuing instant queries or falling back
to `kube_*` metrics / Loki, but incident timelines built purely from range queries are
unreliable. Candidate to file upstream.

---

## 7. `bash` / `kubectl` tool calls blocked by approval prompt

**Status:** Workaround available
**Command affected:** `holmes investigate` in non-interactive (piped) mode

### Symptom

Investigation stalls or skips steps; commands like `kubectl -n app describe pod <x>` are
reported as requiring approval and never execute when output is piped to a file
(`| tee findings/...txt`).

### Root Cause

HolmesGPT's `bash` toolset requires interactive approval for shell commands. In non-interactive
runs there is no TTY to approve, so the call is declined.

### Fix

Rely on the structured Kubernetes toolsets (`kubernetes_jq_query`,
`kubernetes_resource_*`) which do not require bash approval, or run interactively and approve.
The agent generally routes around blocked bash calls automatically.

---

## 8. `fetch_pod_logs` returns empty for crashed pods

**Status:** Workaround available (Loki fallback)
**Command affected:** `kubernetes/logs` (`fetch_pod_logs`)

### Symptom

Empty log output for pods in `CrashLoopBackOff` — the container has already restarted so the
previous container's logs are gone from the kubelet.

### Root Cause

`fetch_pod_logs` reads the current container's live logs. A crashed/restarted container's prior
output is not retained by the kubelet past the restart.

### Fix

Loki retains the shipped history. The agent falls back to `grafana_loki_query` and recovers the
full crash log stream — this is a genuine advantage of having Loki in the stack. Ensure Promtail
is running and the `grafana/loki` toolset is configured (issue 5).
