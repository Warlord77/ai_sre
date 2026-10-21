# cronjob_sidecar_blocks_completion_hotel_reservation

Perfect! The frontend also has NO readiness probe. Despite the Consul connection errors during initialization, the frontend logs show "Successfull" and "Serving http", meaning it continued to start even though it couldn't retrieve service instances from Consul. This means the frontend is serving HTTP requests but doesn't have proper service discovery information for the backend services, causing requests to timeout.

## ROOT CAUSE

**Faulty Component(s):**
- **Deployment: `consul`** in namespace `hotel-reservation`
- **Deployment: `frontend`** in namespace `hotel-reservation`

**Root Cause:**

The Consul deployment is missing a readiness probe, causing a race condition during application startup that breaks service discovery and leads to request timeouts.

**What is misconfigured:**

1. **Consul deployment has no readiness probe**: Without a readiness probe, Kubernetes immediately marks the Consul pod as Ready when it starts, even though Consul's HTTP API server on port 8500 takes approximately 500ms to start listening (starts at 06:29:57.000Z, HTTP server ready at 06:29:57.535Z).

2. **Frontend deployment has no readiness probe**: The frontend starts simultaneously with Consul (both at 06:29:57Z) and immediately tries to query Consul's HTTP API to discover backend services (search, profile, recommendation, user, reservation). Because Consul isn't ready yet, these queries fail with "connection refused" errors.

3. **Frontend continues serving despite failed service discovery**: The frontend proceeds to serve HTTP requests even though it couldn't retrieve service instance information from Consul during initialization, resulting in incomplete or missing backend service connections.

**Why it breaks the application:**

The wrk2 load testing job consistently reports **186 timeout errors per 30-second test run** (out of ~3158 total requests). These timeouts occur because the frontend cannot properly route requests to backend services - it either has no service discovery information or incomplete information due to the failed Consul queries during startup. When client requests arrive at the frontend, it cannot successfully forward them to the appropriate backend services, causing the requests to timeout.

**Evidence:**

1. Consul deployment has no readiness or liveness probes (confirmed via `kubectl get deployment consul -o jsonpath`)
2. Consul logs show HTTP server started at `2026-10-21T06:29:57.535Z` with message "Starting server: address=[::]:8500"
3. Frontend logs show 6 connection refused errors at `2026-10-21T06:29:57Z` trying to query Consul for services: srv-search, srv-profile, and srv-recommendation
4. Frontend proceeded to "Serving http" despite these failures
5. wrk2 load test consistently shows `Socket errors: connect 0, read 0, write 0, timeout 186` across multiple test rounds (06:30:40, 06:31:11, 06:31:42, 06:32:13, 06:32:44, 06:33:15, 06:33:46)
6. Alert firing: `KubePodNotReady` for audit-log-archiver pods (unrelated to main issue - these are CronJob pods with completed main containers)
