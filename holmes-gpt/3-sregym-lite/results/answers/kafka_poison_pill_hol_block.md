# kafka_poison_pill_hol_block

Perfect! Now I have all the information I need. Let me create a comprehensive summary of my findings.

## ROOT CAUSE

### Faulty Component #1: **Service/jaeger** (astronomy-shop namespace)

**Root Cause:** The `jaeger` Service is misconfigured as an ExternalName service with an invalid `selector` field. ExternalName services should not have selectors because they don't route to pods - they create DNS CNAME records. The presence of the selector `app: jaeger` causes DNS resolution to fail because:
1. ExternalName services with selectors are invalid configurations
2. The DNS lookup for `jaeger` fails with "no such host" errors
3. This prevents the otel-collector-agent from exporting traces to the Jaeger backend

**Evidence:**
- Service configuration shows `type: ExternalName` with `externalName: otel-collector.observe.svc.cluster.local` AND `selector: {app: jaeger}` - this combination is invalid
- otel-collector-agent logs show repeated errors: `dial tcp: lookup jaeger on 10.96.0.10:53: no such host`
- The old otel-collector-agent pod (otel-collector-agent-jqxsh) crashed with: `Error: failed to shutdown service after error: failed to shutdown meter provider: failed to upload metrics: Post "http://otel-collector:4318/v1/metrics": dial tcp 10.96.181.215:4318: connect: connection refused`
- Multiple application pods (recommendation, product-reviews, product-catalog) log: `Transient error StatusCode.UNAVAILABLE encountered while exporting traces/logs to otel-collector:4317`

**Impact:** Distributed tracing is broken - traces cannot be exported from application services through the otel-collector-agent to the Jaeger backend, degrading observability.

---

### Faulty Component #2: **Kafka topic `orders-fulfillment`** (data corruption at offset 20)

**Root Cause:** The Kafka topic `orders-fulfillment` contains a malformed JSON record at offset 20. The `orders-validator` consumer successfully processed records at offsets 0-19 (order IDs ORD-100000 through ORD-100019), but encountered a JSON parsing error at offset 20 with the message: `Expecting value: line 1 column 35 (char 34)`. This indicates the record at offset 20 has invalid JSON syntax, likely from seed data preloaded in the Kafka image `ghcr.io/open-telemetry/demo:2.2.0-kafka`.

**Evidence:**
- orders-validator logs from pod `orders-validator-848f778859-j8xrw`:
  ```
  2026-10-21 10:13:14,966 INFO processed order_id=ORD-100019 committed_offset=20
  2026-10-21 10:13:14,967 ERROR record validation failed at offset=20: Expecting value: line 1 column 35 (char 34)
  2026-10-21 10:13:14,967 ERROR partition processing paused at offset=20
  2026-10-21 10:13:29,985 ERROR partition remains paused at offset=20
  2026-10-21 10:13:45,001 ERROR partition remains paused at offset=20
  ```
- The consumer code in ConfigMap `orders-pipeline-scripts` shows it expects JSON with an `order_id` field: `obj = json.loads(value.decode("utf-8"))` followed by validation that `"order_id" in obj`
- The consumer permanently pauses partition processing on validation failure, blocking all subsequent order processing
- Kafka logs show the topic was created with initial high watermark 0, and the first 20 records (ORD-100000 to ORD-100019) were preloaded before the order-stream producer started

**Impact:** Order validation pipeline is completely blocked - the `orders-validator` deployment cannot process any orders beyond offset 19, preventing orders from being validated and forwarded to the `orders-processed` topic. This breaks the order fulfillment workflow.
