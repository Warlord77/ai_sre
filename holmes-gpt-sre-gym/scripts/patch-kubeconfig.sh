#!/usr/bin/env bash
# Patch the kind kubeconfig so a Docker container on macOS can reach the API server.
#
# kind writes the API server as https://127.0.0.1:<port>, which inside a container
# resolves to the container's own loopback — not the kind control-plane on the Mac.
# Rewriting to host.docker.internal lets the HolmesGPT container reach it.
#
# See issues.md #3 (unreachable API server) and #4 (resulting TLS SAN mismatch).
#
# Usage: scripts/patch-kubeconfig.sh [context] [out-file]
set -euo pipefail

CONTEXT="${1:-kind-sre-gym}"
OUT="${2:-/tmp/kube-docker.yaml}"

kubectl config view --context "$CONTEXT" --minify --raw \
  | sed 's|https://127.0.0.1:|https://host.docker.internal:|g' \
  > "$OUT"

echo "Patched kubeconfig for context '$CONTEXT' -> $OUT"
