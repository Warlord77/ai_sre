**ROOT CAUSE**

- **Faulty component:** `Pod frontend-proxy-7b7cd5fb4-lqwtd (Deployment frontend‑proxy)`.  
- **Failure:** The container was terminated with **OOMKilled** (`exitCode 137`) and entered a **CrashLoopBackOff**.  
- **Why it breaks the application:** The frontend‑proxy is the entry point for all user traffic. When it is repeatedly killed for out‑of‑memory, the proxy cannot forward requests to the downstream services (e.g., checkout, recommendation). This produced the flood of “connection refused” errors seen in the frontend logs and caused downstream failures such as the “shipping quote failure” and overall unavailability of the OpenTelemetry Demo Astronomy Shop.

**Evidence**

| Resource | Evidence |
|----------|----------|
| Pod status (frontend‑proxy) | `state.waiting.reason: CrashLoopBackOff` and `lastState.terminated.reason: OOMKilled` (restartCount 4) – observed via `kubernetes_jq_query` on the pod. |
| Container logs (frontend‑proxy) | Warnings about missing OTEL env vars, but no other errors; the OOM kill is reflected in the pod status rather than explicit log messages. |
| Deployment spec (frontend‑proxy) | Memory limit set to **65 Mi** (`.spec.template.spec.containers[0].resources.limits.memory: "65Mi"`). |
| Application logs (frontend) | Numerous `connection refused` messages to service IPs (e.g., `10.96.208.125:8080`, `10.96.178.214:8080`), indicating the proxy could not reach downstream services. |
| Events (frontend‑proxy) | `Warning BackOff` event confirming the container restart loop. |

**Fix**

Increase the memory limit for the `frontend-proxy` deployment to a value that comfortably fits its runtime needs (e.g., `256Mi` or higher) and redeploy:

```yaml
# Patch example (apply with kubectl)
kubectl -n astronomy-shop set resources deployment/frontend-proxy \
  --limits=memory=256Mi \
  --requests=memory=128Mi
```

After applying the new limits, the pod should start without OOM kills, the CrashLoopBackOff will resolve, and the frontend will be able to route traffic to the microservices, restoring normal operation of the OpenTelemetry Demo Astronomy Shop.
