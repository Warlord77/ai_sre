**ROOT CAUSE**

- **Faulty component(s)**
  - `DaemonSet/otel-collector-agent` pods (`otel-collector-agent-nnht6`, `otel-collector-agent-psv5t`, `otel-collector-agent-v2xsb`)

- **Why it breaks the application**
  - The collector pods start correctly but the **health‑check extension never binds to the port expected by the probes (13133)**.  
  - Liveness and readiness probes (`http-get http://:13133/`) therefore fail (`dial tcp …: connection refused`).  
  - Because the pods are marked *Unready*, the `otel-collector` Service reports no ready endpoints.  
  - Down‑stream services (e.g. `product-catalog`, `frontend`) attempt to export telemetry or call other services via the collector and receive **connection‑refused** errors, which cascade into the many “UNAVAILABLE” and “FAILED” messages seen in the frontend logs.

- **Evidence**
  - **Events** – multiple `Warning  Unhealthy` entries for each collector pod:  
    ```
    Readiness probe failed: Get "http://10.244.162.176:13133/": dial tcp ... connection refused
    Liveness probe failed: Get "http://10.244.162.176:13133/": dial tcp ... connection refused
    ```
  - **Collector pod logs** – health‑check extension starts, but no log shows the HTTP server listening on 13133; only the extension start message appears.  
  - **Product‑catalog logs** – exporter cannot reach the collector:  
    ```
    exporter export timeout: rpc error: code = Unavailable desc = connection error: dial tcp 10.96.254.140:4317: connect: connection refused
    ```
  - **Frontend logs** – numerous `UNAVAILABLE` errors when calling other services (cart, product‑catalog, email, flagd) that stem from the collector being unavailable and the services failing to complete their request pipelines.

**Remediation**
1. **Update the collector config** (`otel-collector-agent` ConfigMap) to include a health‑check receiver bound to port 13133, e.g.:

   ```yaml
   extensions:
     health_check:
       endpoint: "0.0.0.0:13133"
   service:
     extensions: [health_check]
   ```

2. **Or adjust the probes** in the DaemonSet to match the actual health endpoint (if a different port is used).  
3. Apply the corrected ConfigMap and roll the DaemonSet (`kubectl rollout restart daemonset otel-collector-agent -n astronomy-shop`).  
4. Verify that the collector pods become Ready (`kubectl get pods -l component=agent-collector -n astronomy-shop`) and that the `otel-collector` Service shows ready endpoints.  
5. Confirm that downstream services no longer log connection‑refused errors and that traces appear in Jaeger.
