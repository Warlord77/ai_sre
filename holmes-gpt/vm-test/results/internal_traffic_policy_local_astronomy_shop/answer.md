**Investigated components**

| Kind | Name | Namespace | Status / Evidence |
|------|------|-----------|-------------------|
| **Pod** | `recommendation-74758c88-8nn94` | `astronomy-shop` | Ready = `True`; container listening on port 8080 (log shows successful handling of `ListRecommendations` calls). |
| **Service** | `recommendation` | `astronomy-shop` | ClusterIP = `10.96.61.101`, selector `opentelemetry.io/name=recommendation` matches the pod labels. |
| **Pod** | `otel-collector-agent-ggftv` / `otel-collector-agent-tdbjs` / `otel-collector-agent-zjjvf` | `astronomy-shop` | Repeated error logs: <br>```\nerror kubeletstatsreceiver/... call to /stats/summary endpoint failed\ntls: failed to verify certificate: x509: cannot validate certificate for 172.18.0.X because it doesn't contain any IP SANs\n``` |
| **Alert** | `ServiceEndpointDown` (deployment = `recommendation`) | `astronomy-shop` | Firing since `2026‑10‑23T10:54:49Z`; reason: “Service endpoint recommendation.astronomy-shop:8080 is unreachable.” |

**Findings**

* The **recommendation** pod is running, ready, and serving HTTP on port 8080 – no errors in its logs.
* The **recommendation** Service correctly selects the pod (labels match) and has a valid ClusterIP.
* The **only observed failures** are from the OpenTelemetry Collector agents’ **kubeletstatsreceiver**. Every scrape of the kubelet `/stats/summary` endpoint fails with a TLS verification error because the kubelet’s serving certificate does **not contain the node’s IP address as a Subject Alternative Name (SAN)**.
* The collector’s failure to scrape kubelet metrics prevents it from exposing node‑level metrics that the blackbox exporter (or other monitoring components) rely on for health checks. Consequently the `ServiceEndpointDown` alert for the recommendation service is triggered even though the service itself is reachable.

**ROOT CAUSE**

* **Faulty component:** `kubeletstatsreceiver` in the OpenTelemetry Collector agents (`otel-collector-agent-ggftv`, `otel-collector-agent-tdbjs`, `otel-collector-agent-zjjvf`).
* **Root cause:** kubelet TLS certificates lack the node IP in the SAN field, causing TLS verification to fail for the collector’s HTTPS request to `https://<node‑IP>:10250/stats/summary`. The collector logs the error repeatedly, leading to missing metrics and a downstream alert that the recommendation service endpoint is unreachable.
* **Evidence:** Repeated error log lines (see collector logs) showing `tls: failed to verify certificate … does not contain any IP SANs`; the alert `ServiceEndpointDown` is firing for the recommendation service despite the pod being ready.  

**Remediation**

1. **Regenerate kubelet certificates** to include the node’s IP address as an IP SAN (or use a SAN‑compatible wildcard DNS name).  
2. **Alternatively**, adjust the OpenTelemetry Collector configuration for `kubeletstatsreceiver` to skip TLS verification (`insecure_skip_verify: true`) if certificate regeneration is not immediately possible.  
3. After fixing the certificate or collector config, verify that the collector logs no longer contain the TLS error and that the `ServiceEndpointDown` alert clears.  

All other application pods and services are healthy; the incident is isolated to the collector’s inability to scrape kubelet metrics due to the TLS SAN misconfiguration.
