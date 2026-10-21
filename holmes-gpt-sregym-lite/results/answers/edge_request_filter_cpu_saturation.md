# edge_request_filter_cpu_saturation

Perfect! Now I have all the evidence I need. Let me create a comprehensive summary of the root cause.

## ROOT CAUSE

**Faulty Component(s):**
- **Kind:** ConfigMap
- **Name:** `otel-collector-agent` 
- **Namespace:** `astronomy-shop`
- **Affected Resource:** DaemonSet `otel-collector-agent` in namespace `astronomy-shop`

**Root Cause:**

The OpenTelemetry Collector agent configuration contains an incorrect endpoint for trace export. The `otlp/jaeger` exporter is configured with `endpoint: jaeger:4317`, which uses a short hostname that cannot be resolved via DNS.

**Why it breaks the application:**

1. **DNS Resolution Failure:** The hostname `jaeger` (without namespace qualification) cannot be resolved. While ExternalName services exist (`jaeger`, `jaeger-agent`, `jaeger-collector`, `jaeger-query`) pointing to `otel-collector.observe.svc.cluster.local`, these services have selectors (`app: jaeger`, etc.) that don't match any pods, making them non-functional for DNS resolution.

2. **Collector Pod Crashes:** The previous otel-collector-agent pod (`otel-collector-agent-jf6pw`) crashed due to this misconfiguration, with errors showing:
   - `lookup jaeger on 10.96.0.10:53: no such host`
   - `failed to shutdown service after error: failed to shutdown meter provider`
   - The pod was marked `Unhealthy` and eventually replaced

3. **Trace Export Failures:** Applications attempting to send traces experience export failures, though the current collector pod (`otel-collector-agent-cp2fc`) continues running because it hasn't yet hit the fatal error condition.

**Evidence:**

1. **ConfigMap misconfiguration** (from `otel-collector-agent` ConfigMap):
   ```yaml
   exporters:
     otlp/jaeger:
       endpoint: jaeger:4317  # ← INCORRECT: should be fully qualified
   ```

2. **DNS lookup failures** (from `otel-collector-agent-jf6pw` logs at 06:54:00-06:54:03):
   ```
   lookup jaeger on 10.96.0.10:53: no such host
   Exporting failed. Dropping data.
   ```

3. **Pod crash and replacement** (from events at 06:54:03):
   ```
   Unhealthy: Readiness probe failed: HTTP probe failed with statuscode: 503
   Killing pod/otel-collector-agent-jf6pw
   SuccessfulCreate: Created pod: otel-collector-agent-cp2fc
   ```

4. **Application export errors** (from application logs):
   - `product-catalog`: `connection refused: dial tcp 10.96.36.9:4317: connect: connection refused`
   - `quote`: `Failed to connect to otel-collector port 4318`
   - `recommendation`: `StatusCode.UNAVAILABLE encountered while exporting logs to otel-collector:4317`

**Fix:**

Change the endpoint in the `otel-collector-agent` ConfigMap from `endpoint: jaeger:4317` to `endpoint: otel-collector.observe.svc.cluster.local:4317` to use the fully qualified domain name that correctly resolves to the otel-collector service in the observe namespace.
