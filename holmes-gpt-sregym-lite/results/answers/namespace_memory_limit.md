# namespace_memory_limit

Perfect. I now have all the evidence needed. Let me create a comprehensive summary of the root cause.

## ROOT CAUSE

**Faulty Component:**
- **Kubernetes Resource:** `Deployment/search` in namespace `hotel-reservation`
- **Associated Resource:** `ResourceQuota/memory-limit-quota` in namespace `hotel-reservation`

**Root Cause:**

The `search` deployment is unable to create pods due to a misconfigured ResourceQuota. The ResourceQuota `memory-limit-quota` was created at `2026-10-21T10:48:34Z` with a hard limit of `memory: 1Gi`. When a ResourceQuota tracks memory resources, Kubernetes enforces that **all pods must explicitly specify memory requests and/or limits** in their container specifications.

The `search` deployment's pod template only specifies CPU resources:
```yaml
resources:
  limits:
    cpu: "1"
  requests:
    cpu: "100m"
```

It lacks memory specifications entirely. When the original search pod (`search-7b5d46778f-jftsm`) was killed at `10:48:41` (11 seconds after the quota was created), the ReplicaSet attempted to recreate it but was blocked by the admission controller with the error:

```
Error creating: pods "search-7b5d46778f-*" is forbidden: failed quota: memory-limit-quota: must specify memory for: hotel-reserv-search
```

**Why it breaks the application:**

1. The `search` service has **0 ready replicas** out of 1 desired
2. No search pods exist in the cluster
3. The search service is a critical component for hotel search functionality
4. Metrics confirm the search service is down: `up{instance="search.hotel-reservation:9092"}` = 0
5. The frontend service depends on the search service via Consul service discovery

**Evidence:**

1. **Deployment status:** `search` deployment shows `ReplicaFailure: True` with reason `FailedCreate`
2. **Events:** Multiple `FailedCreate` events from ReplicaSet `search-7b5d46778f` with message: `"failed quota: memory-limit-quota: must specify memory for: hotel-reserv-search"`
3. **Pod count:** Zero search pods exist (confirmed via pod listing)
4. **Resource specification:** `kubectl get deployment search -n hotel-reservation -o json` shows only CPU limits/requests, no memory specifications
5. **ResourceQuota:** Created at `10:48:34Z` with `spec.hard.memory: 1Gi`
6. **Timeline:** Original search pod killed at `10:48:41Z`, recreation attempts failed immediately after
7. **Metrics:** Prometheus shows `up{job="hotel-reservation-application", instance="search.hotel-reservation:9092"} = 0`

**Fix Required:**

Add memory requests and limits to the search deployment's container specification, for example:
```yaml
resources:
  limits:
    cpu: "1"
    memory: "512Mi"  # Add this
  requests:
    cpu: "100m"
    memory: "256Mi"  # Add this
```

Alternatively, if the ResourceQuota is incorrectly configured, it should be modified to use `requests.memory` and `limits.memory` instead of just `memory`, or removed if not needed.
