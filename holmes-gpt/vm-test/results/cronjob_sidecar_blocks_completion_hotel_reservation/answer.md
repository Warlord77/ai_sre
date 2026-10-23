**Investigation summary**

| Entity | Checked / Findings |
|--------|--------------------|
| **Deployments** (hotel‑reservation) | All 19 deployments have 1 replica and are `Ready`. |
| **Pods** (hotel‑reservation) | All pods are `Running`. Several pods (geo, profile, rate, recommendation, reservation, user) show recent restarts (2‑3). |
| **Reservation pod logs** (`reservation‑57b8ccd5dc‑rthlj`) | At start‑up the pod logged `panic: no reachable servers` when trying to connect to MongoDB (`mongodb‑reservation:27017`). After a retry the DB connection succeeded and the service started normally. |
| **Profile pod logs** (`profile‑85c6f67954‑mmjdm`) | Same `panic: no reachable servers` error when connecting to its MongoDB (`mongodb‑profile:27017`). |
| **MongoDB pods** | All MongoDB pods are `Running` and their logs show only normal slow‑query warnings – no crashes. |
| **Kubernetes Services** (hotel‑reservation) | Service objects for `mongodb‑reservation`, `mongodb‑profile`, etc. exist with valid ClusterIP addresses. |
| **Endpoints** | Endpoints for the MongoDB services resolve to pod IPs (e.g. `mongodb‑reservation` → 10.244.110.170). |
| **CoreDNS pods** (`coredns‑…`) | Both CoreDNS pods report `Ready=True`. |
| **CoreDNS Service** | `kube-dns` exists with ClusterIP 10.96.0.10. |
| **CoreDNS ConfigMap** | Standard CoreDNS Corefile, no syntax errors. |
| **DNS resolution test** (`tcp_check`) | `tcp_check` for `mongodb‑reservation:27017` and `mongodb‑profile:27017` fails with *“could not resolve host …”*. This indicates that DNS name resolution from within the cluster is broken for those service names. |
| **Prometheus metrics** | No `coredns_dns_requests_total` data – suggests CoreDNS metrics are not being scraped (possible scrape failure). |
| **Events** | Direct `kubectl get events` query ran out of memory; no event data was retrieved. |

**Root cause**

- The **reservation** and **profile** services panic because they cannot resolve the DNS names of their MongoDB back‑ends (`mongodb‑reservation`, `mongodb‑profile`).  
- DNS resolution fails cluster‑wide despite CoreDNS pods being `Ready`. The failure is confirmed by `tcp_check` returning “could not resolve host”.  
- The underlying issue is a **CoreDNS service disruption** (likely the CoreDNS pods are not actually serving DNS queries even though they report `Ready`, or the `kube-dns` Service is not reachable due to a networking problem or a mis‑configured `coredns` ConfigMap/iptables rule).  

**Evidence**

- `reservation` pod log: `panic: no reachable servers` when trying to connect to `mongodb‑reservation:27017`.  
- `profile` pod log: identical panic for `mongodb‑profile:27017`.  
- `tcp_check` for `mongodb‑reservation:27017` → *could not resolve host*.  
- CoreDNS pods `Ready=True` but no DNS query metrics (`coredns_dns_requests_total` empty).  
- Endpoints for the MongoDB services exist and are reachable by IP, confirming the problem is name resolution, not pod failure.

**Impact**

- **Affected**: `deployment/reservation`, `deployment/profile` (and any other workloads that depend on MongoDB services via DNS).  
- **Checked, healthy**: All MongoDB pods, other micro‑services (frontend, geo, rate, recommendation, etc.) – they can start because they either use cached DNS entries or do not hit the DB at start‑up.  
- **Changed during the window for another reason**: None observed.  

**Remediation steps**

1. **Restart CoreDNS** – `kubectl rollout restart deployment/coredns -n kube-system`. This forces a fresh DNS server start and often clears transient state.  
2. **Verify CoreDNS health** – after restart, run `kubectl exec -n kube-system <coredns-pod> -- dig mongodb-reservation.hotel-reservation.svc.cluster.local`. The query should return the correct pod IP.  
3. **Check network policies / iptables** – ensure no policy blocks traffic from the `hotel-reservation` namespace to the `kube-dns` Service (port 53/UDP/TCP).  
4. **Confirm Prometheus scraping** – add a scrape target for `coredns` if missing, to monitor DNS request rates and errors.  
5. **Monitor** – watch the `reservation` and `profile` pods for further restarts; they should stay healthy once DNS works.  

**Conclusion**

The incident is caused by a DNS resolution failure in the cluster, preventing the reservation and profile services from locating their MongoDB back‑ends. Restoring CoreDNS functionality resolves the issue.
