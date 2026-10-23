#!/usr/bin/env bash
# Runs `holmes ask` in Docker against the current kind cluster with the .env model.
# Usage: scripts/holmes-ask.sh "question" [--mcp]
#   --mcp also attaches SREGym's Prometheus/Loki/Jaeger MCP servers (needs scripts/mcp-server.sh start).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

QUESTION=${1:-"Which pods are running in kube-system and are any of them unhealthy? Answer in 5 lines."}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
kubectl config view --minify --raw > "$WORK/kubeconfig.yaml"

cat > "$WORK/holmes-config.yaml" <<'EOF'
toolsets:
  kubernetes/core:
    enabled: true
  kubernetes/logs:
    enabled: true
EOF
if [[ ${2:-} == --mcp ]]; then
  cat >> "$WORK/holmes-config.yaml" <<EOF
mcp_servers:
  sregym-prometheus:
    description: PromQL queries against the cluster Prometheus (metrics)
    config: {url: "http://host.docker.internal:${MCP_SERVER_PORT:-9954}/prometheus/sse", mode: sse}
  sregym-loki:
    description: LogQL queries against the cluster Loki (pod logs, including from deleted pods)
    config: {url: "http://host.docker.internal:${MCP_SERVER_PORT:-9954}/loki/sse", mode: sse}
  sregym-jaeger:
    description: Distributed traces from Jaeger (service call graph, latency, errors)
    config: {url: "http://host.docker.internal:${MCP_SERVER_PORT:-9954}/jaeger/sse", mode: sse}
EOF
fi
chmod 755 "$WORK"; chmod 644 "$WORK"/*

hosts=()
for h in ${HOLMES_EXTRA_HOSTS:-}; do hosts+=(--add-host "$h"); done
dockr run --rm --network host --add-host host.docker.internal:127.0.0.1 "${hosts[@]}" \
  -e OPENAI_API_KEY -e OPENAI_API_BASE -e KUBECONFIG=/work/kubeconfig.yaml -v "$WORK:/work" \
  "$HOLMES_IMAGE" ask "$QUESTION" --model "$MODEL" --config /work/holmes-config.yaml \
  --no-interactive --max-steps "${HOLMES_MAX_STEPS:-15}"
