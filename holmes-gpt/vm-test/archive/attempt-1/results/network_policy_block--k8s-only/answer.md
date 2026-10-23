**Affected (evidence of failure)**  

| Kind / Name | Evidence |
|-------------|-----------|
| **Pod `reservation-57b8ccd5dc-nzdqg`** (deployment *reservation*) | `containerStatuses[0].lastState.terminated.reason: "Error"` / `exitCode: 2` (see JSON output). Log snippet: `panic: no reachable servers` (failed to connect to `mongodb-reservation:27017`). Event: `Back-off restarting failed container` (restartCount = 7). |
| **Pod `geo-766c64f6b4-pnhsv`** (deployment *geo*) | Event `Back-off restarting failed container hotel-reserv-geo` (restartCount = 3). |
| **Pod `rate-b6dc6465f-jwmjb`** (deployment *rate*) | Event `Back-off restarting failed container hotel-reserv-rate` (restartCount = 3). |
| **Pod `profile-85c6f67954-sj785`** (deployment *profile*) | Event `Back-off restarting failed container hotel-reserv-profile` (restartCount = 1). |
| **Pod `user-5c4d969c85-jz5h6`** (deployment *user*) | Event `Back-off restarting failed container hotel-reserv-user` (restartCount = 7). |
| **Pod `recommendation-6bf7689fdb-zndmk`** (deployment *recommendation*) | Event `Back-off restarting failed container hotel-reserv-recommendation` (restartCount = 1). |

All of the above pods show **BackOff** events and/or container termination with `reason: "Error"` and non‑zero exit codes, indicating they repeatedly crashed and were restarted.

**Checked, healthy**  

| Kind / Name | Evidence |
|-------------|-----------|
| All MongoDB pods (`mongodb‑*`) | `status.phase: Running`, `containerStatuses[0].ready: true`, no crash events. |
| Service mesh / Consul / Jaeger pods | Normal `Scheduled`, `Started`, `Ready` events; no errors. |
| Deployments `frontend`, `search` | Pods running, no BackOff, no error logs. |

**Changed during the window for another reason**  

| Resource | Change | Reason |
|----------|--------|--------|
| PVCs (`reservation-pvc`, `geo-pvc`, `rate-pvc`, `profile-pvc`, `user-pvc`, `recommendation-pvc`) | `ProvisioningSucceeded` at ~04:56 UTC | Persistent volumes were created late, causing the corresponding MongoDB pods to start later than their dependent services. |
| MongoDB pods (`mongodb‑*`) | `Started` at ~04:56 UTC | Started only after PVCs became bound. |

**Root cause**  

- **Faulty component(s):** The **application pods** (`reservation`, `geo`, `rate`, `profile`, `user`, `recommendation`) repeatedly crashed because they attempted to open a MongoDB connection **before the corresponding MongoDB pod was ready**.  
- **Why it breaks the application:** Each service reads its database URL from the environment (e.g., `mongodb-reservation:27017`). When the MongoDB pod is not yet running (PVC still provisioning), the driver returns “no reachable servers”, the Go code panics, and the container exits with `exitCode = 2`. Kubernetes then applies a back‑off restart policy, leading to the observed `BackOff` events and high restart counts.  
- **Evidence:**  
  1. `reservation` pod JSON shows `lastState.terminated.reason: "Error"` and `exitCode: 2` with logs `panic: no reachable servers`.  
  2. Event list contains `Back-off restarting failed container` for each affected pod.  
  3. PVC provisioning events (`ProvisioningSucceeded`) occur **after** the initial start of the dependent pods (≈04:56 UTC), while the MongoDB pods only become ready at the same time.  

**Remediation suggestions**  

1. **Add a readiness probe** (or init container) to each service that waits for its MongoDB endpoint to become reachable before starting the main container.  
2. **Ensure PVCs are pre‑provisioned** (or use a storage class that provisions instantly) so MongoDB pods start before dependent services.  
3. **Adjust deployment ordering**: set `dependsOn` via Helm hooks or use `postStart` scripts to retry DB connections with exponential back‑off instead of panicking.  

Implementing one or more of these changes will prevent the services from crashing on startup and eliminate the BackOff cycles.
