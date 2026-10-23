**Affected**  
- **Deployment** `nginx-thrift` (namespace `social‑network`) – `Available` = `<none>` (deployment status `MinimumReplicasUnavailable`).  
- **Pod** `nginx-thrift-6c5bcfcb8f-fwpjs` – `Ready` = `False`; `status.conditions[Ready].reason` = `ContainersNotReady`; `status.containerStatuses[0].state.waiting.reason` = `CrashLoopBackOff`; `lastState.terminated.reason` = `OOMKilled` (exit code 137).  

**Checked, healthy**  
- All other deployments in `social‑network` report `AVAILABLE = 1` and have no restart or OOM events.  
- Init container `alpine-container` completed successfully (`exitCode 0`).  

**Changed during the window for another reason**  
- None observed for `nginx-thrift`; the pod’s restarts are due to the OOM‑induced crash loop, not a rollout.  

**Root Cause**  
- The `nginx-thrift` container is configured with **memory limits** `requests: 128 Mi`, `limits: 256 Mi` (see deployment spec).  
- During start‑up the container exceeds its limit, is **OOM‑killed** (`lastState.terminated.reason: OOMKilled`), and the kubelet restarts it, entering **CrashLoopBackOff**.  
- The pod never becomes ready, so the `nginx-thrift` service has no endpoints, breaking any downstream microservices that depend on it (e.g., API gateway, other Thrift clients).  

**Evidence**  
- Pod description shows `Ready` = `False` with `ContainersNotReady` and `CrashLoopBackOff` (container status).  
- `lastState.terminated.reason: OOMKilled` (exit code 137) confirms memory exhaustion.  
- Deployment status reports `MinimumReplicasUnavailable`.  
- Deployment spec lists `resources.limits.memory: "256Mi"` (insufficient for the workload).  

**Remediation**  
1. Increase the memory limits for the `nginx-thrift` container (e.g., `requests: 256Mi`, `limits: 512Mi`).  
2. Apply the updated Helm values or edit the deployment, then roll out the change.  
3. Verify the pod becomes `Ready` and the service regains endpoints.  

After the limit adjustment, the pod should start without OOM, exit the CrashLoopBackOff, and restore normal operation of the Social Network application.
