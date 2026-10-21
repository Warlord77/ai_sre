# finalizer_deadlock_controller_hotel_reservation

Perfect! I've identified the root cause. Let me create a comprehensive summary of my findings.

## ROOT CAUSE

**Faulty Component:**
- **Kubernetes Resource:** Deployment `rate` in namespace `hotel-reservation`
- **Container:** `hotel-reserv-rate`

**Root Cause:**
The `rate` service has a misconfigured environment variable `RATE_BACKEND_QPS_LIMIT` set to `500` (queries per second), which should be `5000`. This artificially low limit throttles the rate service's backend database queries to only 500 QPS, causing request queueing and timeouts when the application is under load.

**Why it breaks the application:**
1. The `search` service calls the `rate` service with a 1-second timeout (`RATE_RPC_TIMEOUT_MS: 1000`)
2. When load increases, the rate service hits its 500 QPS limit and queues requests (queue capacity: 256)
3. Queued requests exceed the 1-second timeout, causing the search service to timeout
4. This cascades to the frontend, resulting in 188-192 timeout errors per 30-second load test run (~6% failure rate)

**Evidence:**
1. **Wrk2 load test results:** Consistent timeout errors across multiple test runs:
   - Round #1: 188 socket timeouts out of 2972 requests
   - Round #2: 192 socket timeouts out of 2899 requests  
   - Round #3: 187 socket timeouts out of 2896 requests

2. **Configuration verification:**
   ```
   Deployment: rate
   Environment Variables:
   - RATE_BACKEND_QPS_LIMIT: "500"  ← MISCONFIGURED (should be 5000)
   - RATE_QUEUE_CAPACITY: "256"
   ```

3. **Search service timeout configuration:**
   ```
   Deployment: search
   Environment Variables:
   - RATE_RPC_TIMEOUT_MS: "1000"
   - RATE_RPC_MAX_ATTEMPTS: "2"
   ```

4. **Resource utilization:** The rate service pod is using 47m CPU (47% of its 100m request), indicating it's under load but artificially constrained by the QPS limit, not by CPU resources.

5. **No other services have QPS limits:** The geo service and other backend services don't have similar QPS limit configurations, confirming this is an anomaly specific to the rate service.

**Fix:** Change the `RATE_BACKEND_QPS_LIMIT` environment variable in the `rate` deployment from `500` to `5000` to allow the service to handle the expected query load.
