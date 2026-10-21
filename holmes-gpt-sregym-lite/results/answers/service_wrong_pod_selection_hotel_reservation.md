# service_wrong_pod_selection_hotel_reservation

Perfect! I now have a complete understanding of the issue. Let me compile the final root cause analysis.

## ROOT CAUSE

**Faulty Component(s):**
- **Deployment:** `rate` (namespace: `hotel-reservation`)
- **Configuration:** Environment variables `RATE_BACKEND_QPS_LIMIT` and `RATE_QUEUE_CAPACITY`

**Root Cause:**

The rate service has a **QPS (Queries Per Second) limit of 500** configured via the `RATE_BACKEND_QPS_LIMIT` environment variable, with a **queue capacity of only 256 requests** (`RATE_QUEUE_CAPACITY`). When the application load exceeds this limit, the rate service cannot process requests fast enough, causing its queue to fill up and requests to be delayed or dropped.

The search service, which calls the rate service, has a **1-second RPC timeout** (`RATE_RPC_TIMEOUT_MS=1000`) and only **2 retry attempts** (`RATE_RPC_MAX_ATTEMPTS=2`). When the rate service is overloaded:
1. Requests to the rate service timeout after 1 second
2. The search service retries once (with backoff)
3. If both attempts fail, the entire hotel search request fails

This cascades to the frontend, resulting in **185 socket timeout errors** reported by the wrk2 load testing job.

**Evidence:**

1. **Rate service configuration** (Deployment `rate`):
   ```
   RATE_BACKEND_QPS_LIMIT: 500
   RATE_QUEUE_CAPACITY: 256
   ```

2. **Search service configuration** (Deployment `search`):
   ```
   RATE_RPC_TIMEOUT_MS: 1000
   RATE_RPC_MAX_ATTEMPTS: 2
   RATE_RPC_INITIAL_BACKOFF_MS: 100
   RATE_RPC_BACKOFF_MULTIPLIER: 2.0
   ```

3. **Timeout errors from load test** (Loki logs from wrk2-job):
   ```
   Socket errors: connect 0, read 0, write 0, timeout 185
   ```

4. **Trace analysis** shows requests taking significantly longer when calling the rate service, with some traces showing durations of 2-3 seconds for operations that should complete in milliseconds.

**Why it breaks the application:**

The rate service acts as a bottleneck. Every hotel search request requires calling the rate service to get pricing information. With the QPS limit set too low (500 req/s) and a small queue (256), the service cannot handle peak load. When requests queue up and timeout, the search service fails, which causes the entire `/hotels` API endpoint to return errors to clients, breaking the hotel reservation functionality.
