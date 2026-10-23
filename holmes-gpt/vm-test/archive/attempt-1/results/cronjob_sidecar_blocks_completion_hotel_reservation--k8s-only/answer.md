**Investigation summary**

| Kind | Name | Evidence of failure | Current status |
|------|------|----------------------|----------------|
| Deployment | `geo` | Event `BackOff` (05:12:33) → pod logs `panic: no reachable servers` (DB init) | Pod `geo‑766c64f6b4‑whxvp` now **Running**, Ready true |
| Deployment | `profile` | Event `BackOff` (05:13:34) → pod logs `panic: no reachable servers` (DB init) | Pod `profile‑85c6f67954‑msz8s` now **Running**, Ready true |
| Deployment | `rate` | Event `BackOff` (05:12:49) → pod logs `panic: no reachable servers` (DB init) | Pod `rate‑b6dc6465f‑422jh` now **Running**, Ready true |
| Deployment | `recommendation` | Event `BackOff` (05:13:03) → pod logs `panic: no reachable servers` (DB init) | Pod `recommendation‑6bf7689fdb‑29hz4` now **Running**, Ready true |
| Deployment | `reservation` | Event `BackOff` (05:12:27) → pod logs `panic: no reachable servers` (DB init) | Pod `reservation‑57b8ccd5dc‑lhz68` now **Running**, Ready true |
| Deployment | `user` | Event `BackOff` (05:12:45) → pod logs `panic: no reachable servers` (DB init) | Pod `user‑5c4d969c85‑gm8pg` now **Running**, Ready true |

All other components (`frontend`, `consul`, `jaeger`, `memcached‑*`, `mongodb‑*`, `search`) are **Running** and **Ready** with no error events.

**Root cause**

- The six micro‑services above all attempt to open a MongoDB connection at start‑up (`Read database URL: mongodb‑<service>:27017`).  
- Their logs show a panic: **`no reachable servers`** caused by the DB client failing to find a reachable MongoDB instance.  
- The MongoDB pods for the corresponding databases were created **after** the dependent services (see creation timestamps: e.g., `mongodb‑geo` 05:12:39 vs. `geo` 05:11:10).  
- Because the services have no start‑up delay or readiness check for the DB, they crash, trigger a `BackOff` restart loop, and only recover once the DB pod becomes ready (as shown by the second successful start in each log).

**Fix recommendation**

1. **Add a start‑up dependency check** – use an init‑container or a startup probe that waits for the corresponding MongoDB service to be reachable (e.g., `nc -z mongodb‑geo 27017` with retries).  
2. **Expose MongoDB readiness** – ensure each MongoDB pod has a proper readiness probe so other pods can reliably wait for it.  
3. **Adjust deployment ordering** – if using Helm, add `helm.sh/hook: pre-install` hooks or `dependsOn` annotations to start DB pods before the micro‑services.  
4. **Increase restart back‑off limits** (optional) to avoid rapid crash loops while the DB is still provisioning.

Implementing any of the above will prevent the “no reachable servers” panic and eliminate the BackOff restarts observed.
