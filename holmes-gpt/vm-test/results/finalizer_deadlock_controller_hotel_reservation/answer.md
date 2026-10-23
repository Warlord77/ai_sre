**ROOT CAUSE**

- **Faulty component:** `Pod reservation-57b8ccd5dc-48mqt` (part of the *reservation* deployment)  
- **What failed:** The container exited with `exitCode 2` and the log line `panic: no reachable servers` while trying to open a MongoDB connection (`mongodb-reservation:27017`).  
- **Why it broke:** The MongoDB pod `mongodb-reservation-5994859869-nsg4b` was not yet running when the reservation pod started. Its `startTime` is `2026‑10‑23T10:06:25Z`, while the reservation pod attempted the DB connection at `2026‑10‑23T10:06:21Z`. The DNS name resolved, but the service had no ready endpoints, causing the driver to report “no reachable servers”. The reservation container crashed, was restarted (restartCount = 2), and succeeded only after the DB became ready.  

**Evidence**

| Resource | Observation |
|----------|-------------|
| `reservation-57b8ccd5dc-48mqt` – container status | `lastState.terminated.exitCode=2`, `reason=Error`, `restartCount=2` |
| Reservation pod logs (first start) | `panic: no reachable servers` (timestamp 10:06:21) |
| MongoDB‑reservation pod (`mongodb-reservation-5994859869-nsg4b`) | `phase=Running`, `ready=true`, `startTime=2026‑10‑23T10:06:25Z` |
| Service `mongodb-reservation` endpoint | IP 10.244.162.189 (pod not ready until 10:06:25) |
| No network policies or probes interfering – probes are `null` |

**Fix**

1. **Add a startup dependency** – make the reservation deployment wait for the MongoDB service to be ready, e.g.:
   - Use an **init container** that polls the MongoDB endpoint (`nc -z mongodb-reservation 27017`) before the main container starts.
   - Or add a **readiness/liveness probe** that retries the DB connection and only marks the pod ready after a successful connection.
2. **Improve connection handling** in the reservation code:
   - Implement retry logic with back‑off on initial DB connection failures.
   - Exit with a non‑crash code (e.g., keep the process alive and retry) to avoid unnecessary restarts.
3. **Optional Helm ordering** – set `dependsOn` or `helm.sh/hook-weight` to ensure the MongoDB StatefulSet/Deployment is created and ready before the reservation deployment is rolled out.  

Applying one of these changes will prevent the reservation pod from crashing on startup due to a transient “no reachable servers” error, eliminating the observed restarts.
