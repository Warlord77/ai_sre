# edge_request_filter_cpu_saturation

Perfect! I have all the evidence I need. The Consul HTTP API started at 07:00:46.257Z, but the frontend pod was created at 07:00:45Z and tried to connect to Consul at 07:00:45Z, which was before Consul was ready to accept connections.

## ROOT CAUSE

**Faulty Component:**
- **Deployment:** `consul` in namespace `hotel-reservation`

**Root Cause:**
The Consul deployment is missing a **readiness probe**, causing a race condition during application startup. When pods start simultaneously, the frontend service attempts to connect to Consul for service discovery before Consul's HTTP API is ready to accept connections.

**Evidence:**

1. **Missing Readiness Probe:** The `consul` deployment has no readiness probe configured, meaning Kubernetes marks the pod as "Ready" immediately when the container starts, not when Consul's HTTP API is actually accepting connections.

2. **Timing Evidence:**
   - Frontend pod created: `2026-10-21T07:00:45Z`
   - Consul pod created: `2026-10-21T07:00:45Z` (same time)
   - Consul HTTP API became ready: `2026-10-21T07:00:46.257Z` (1.2 seconds later)
   - Frontend tried to connect to Consul: `2026-10-21T07:00:45Z` (too early)

3. **Connection Refused Errors:** Frontend logs show repeated connection failures:
   ```
   2026/10/21 07:00:45 grpc/lb/consul: error retrieving instances from Consul: Get "http://consul:8500/v1/health/service/srv-search?passing=1": dial tcp 10.96.99.81:8500: connect: connection refused
   ```

4. **Application Impact:** The frontend's `SearchHandler CheckAvailability` function fails repeatedly because it cannot discover the `srv-search` and `srv-reservation` services via Consul. The frontend logs show continuous errors:
   ```
   SearchHandler CheckAvailability failed
   ```

5. **Transient Issues:** Both `reservation` and `user` pods experienced initial startup failures (1 restart each) due to similar timing issues - `reservation` couldn't reach MongoDB initially, and `user` couldn't resolve the Jaeger hostname during the DNS/service startup window.

**Why It Breaks the Application:**
The frontend depends on Consul for service discovery to locate backend services (search, reservation, profile, recommendation, user). Without a readiness probe, Consul is marked ready before its HTTP API is listening, causing the frontend's gRPC load balancer to fail when querying Consul for service endpoints. This results in the frontend being unable to route requests to backend services, breaking the hotel search and reservation functionality.

**Fix:**
Add a readiness probe to the Consul deployment that checks the HTTP API endpoint (e.g., `http://localhost:8500/v1/status/leader`) to ensure Consul is fully operational before Kubernetes routes traffic to it.
