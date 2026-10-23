**ROOT CAUSE**

- **Faulty component:** `Pod grafana-7b9cbf56f5-qd4qp` (part of the `grafana` Deployment) in namespace **astronomy‑shop**  
- **Why it fails:** The Grafana container attempts to bind to `0.0.0.0:8080`. Port 8080 is already in use by multiple other services in the demo (e.g., `checkout`, `cart`, `currency`, etc.). The bind error (`[Errno 98] address in use`) forces Grafana to repeatedly restart, producing connection‑refused errors when it later tries to call its own HTTP API (`localhost:3000`). This is why the pod shows **3 restarts** and why the logs contain repeated `ERROR` and `WARNING` entries about the address conflict and failed HTTP calls.  
- **Evidence:**  
  - Grafana pod status: `restartCount: 3`, `ready: true` (still running but repeatedly restarted).  
  - Logs (last hour, error‑filtered) contain:  
    ```
    [Errno 98] error while attempting to bind on address ('0.0.0.0', 8080): address in use
    Retry... connection refused to http://localhost:3000/api/admin/provisioning/...
    ```  
  - Other services (checkout, cart, etc.) all expose `containerPort: 8080`, confirming the port conflict.  

**FIX**  
Change Grafana’s HTTP port to a free value (e.g., the default `3000`) by updating its Deployment/ConfigMap (or Helm values) to set `GF_SERVER_HTTP_PORT=3000` (or remove any custom port setting). Then redeploy Grafana. This eliminates the bind error, stops the restart loop, and restores the Grafana UI for the OpenTelemetry demo.
