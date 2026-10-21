# env_variable_shadowing_astronomy_shop

Perfect! The pod now has 3 restarts (it was 2 earlier), confirming the issue is ongoing. Now I have all the evidence needed for a comprehensive root cause analysis.

---

## ROOT CAUSE

**Faulty Component:**
- **Kind:** Deployment
- **Name:** `frontend-proxy`
- **Namespace:** `astronomy-shop`

**Root Cause:**
The `frontend-proxy` deployment has an insufficient memory limit of **65Mi** configured for its Envoy proxy container. Envoy proxy requires more memory to initialize and run properly. The container repeatedly crashes with **OOMKilled** (Out Of Memory Killed) status, causing a crash loop with continuous restarts.

**Why it breaks the application:**
The frontend-proxy serves as the entry point/gateway for the OpenTelemetry Demo Astronomy Shop application. Without a functioning frontend-proxy:
1. External traffic cannot reach the application
2. Load generator requests fail with "Connection refused" errors
3. The entire shopping platform becomes inaccessible to users

**Evidence:**

1. **Pod Status & Restart Loop:**
   - Pod `frontend-proxy-d5f84b788-ksbtr` has 3 restarts and counting
   - Container state: `Terminated` with reason `OOMKilled` (Exit Code 137)
   - Pod events show: `Back-off restarting failed container frontend-proxy`

2. **Deployment Status:**
   - Deployment `frontend-proxy` shows: `READY: <none>`, `DESIRED: 1`, `AVAILABLE: <none>`
   - Deployment condition: `Available: False` with reason `MinimumReplicasUnavailable`

3. **Memory Configuration:**
   - Current memory limit: **65Mi**
   - Comparable services in the same application have much higher limits:
     - `frontend`: 250Mi
     - `ad`: 512Mi
     - `fraud-detection`: 512Mi
     - `cart`: 160Mi
     - `accounting`: 120Mi

4. **Application Impact:**
   - Load generator logs show multiple `ConnectionRefusedError(111, 'Connection refused')` errors for all API endpoints
   - 100% failure ratio for requests attempting to reach the application through the frontend-proxy

5. **Kubernetes Events Timeline:**
   - 07:07:40 - New ReplicaSet scaled up (deployment rollout)
   - 07:07:42-07:07:56 - Multiple OOMKilled terminations
   - Continuous restart attempts with BackOff warnings

**Fix Required:**
Increase the memory limit for the `frontend-proxy` deployment to at least 128Mi-256Mi to allow Envoy proxy to initialize and operate normally.
