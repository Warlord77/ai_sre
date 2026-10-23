**Investigation Summary**

| Entity | Kind | Namespace | Status / Reason | Evidence |
|--------|------|------------|-----------------|----------|
| `frontend‑proxy-7b7cd5fb4-jsr6n` | Pod | astronomy‑shop | **Running** but **Ready = false**; container terminated with **OOMKilled** (exit code 137) – 4 restarts | `kubectl describe pod …` shows `State: Terminated – Reason: OOMKilled`, `Restart Count: 4`, `Limits: memory 65Mi` |
| All other pods (27 total) | Pod | astronomy‑shop | **Running / Ready = true** | `kubectl_tabular_query` shows `READY: true` for every pod except the frontend‑proxy |
| Alert `KubePodNotReady` | Prometheus alert | astronomy‑shop | **Firing** – pod not ready > 1 min | `get_alerts` returned alert with `pod: frontend-proxy-7b7cd5fb4-jsr6n` |
| Node `kind‑worker3` | Node | – | **Healthy** (CPU ≈ 1 %, Memory ≈ 9 %) | `kubectl_top_nodes` |

**Root Cause**

- **Faulty component:** `frontend-proxy-7b7cd5fb4-jsr6n` (container **frontend‑proxy**)  
- **Misconfiguration:** Memory limit set to **65 MiB** (`Limits: memory: 65Mi`). The proxy process exceeds this limit, causing the container to be **OOMKilled** repeatedly (restart count = 4) and entering a back‑off state.  
- **Why it breaks the app:** The frontend‑proxy routes traffic to all other services. When it is OOM‑killed and not ready, the UI cannot reach downstream services, resulting in a complete outage for the shop front‑end.  

**Evidence**

1. `kubectl describe pod` – shows `State: Terminated – Reason: OOMKilled`, `Exit Code: 137`, `Restart Count: 4`, `Limits: memory: 65Mi`.  
2. Pod events include `Warning BackOff` for the container.  
3. Prometheus alert `KubePodNotReady` firing for this pod.  
4. All other pods are running and ready, confirming the issue is isolated to the frontend‑proxy.  

**Remediation**

1. **Increase memory resources** for the `frontend-proxy` container (e.g., `requests: 128Mi`, `limits: 256Mi`).  
2. Apply the change via the Helm chart (or Deployment manifest) and roll out the update:  
   ```bash
   helm upgrade astronomy-shop ./chart \
     --set frontendProxy.resources.limits.memory=256Mi \
     --set frontendProxy.resources.requests.memory=128Mi \
     -n astronomy-shop
   ```
3. Verify the pod becomes Ready and the alert clears:  
   ```bash
   kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=frontend-proxy -n astronomy-shop --timeout=2m
   ```
4. Monitor the pod’s memory usage (`kubectl top pod frontend-proxy-…`) to ensure the new limits are sufficient.  

**Impact**

- **Affected:** `frontend-proxy-7b7cd5fb4-jsr6n` (OOMKilled, not ready).  
- **Checked, healthy:** All other 26 pods in the `astronomy-shop` namespace.  
- **Changed for another reason:** None observed.  

After increasing the memory limits and confirming the pod stabilises, the OpenTelemetry Demo Astronomy Shop should resume normal operation.
