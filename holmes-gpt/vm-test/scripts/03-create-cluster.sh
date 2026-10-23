#!/usr/bin/env bash
# Creates the SREGym kind cluster exactly as upstream (SREGym/kind/setup_kind_cluster.sh:
# 1 control-plane + 3 workers, SREGym node image, /run/udev mounts, Calico v3.29.3),
# then caps each node container's memory so the whole cluster uses NODE_MEMORY x 4.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

NODE_MEMORY=${NODE_MEMORY:-4g}   # 4 nodes x 4g = 16 GB

if kind get clusters 2>/dev/null | grep -qx kind; then
  echo "Cluster 'kind' already exists; skipping creation (kind delete cluster --name kind to recreate)"
else
  (cd "$SREGYM_ABS" && sg docker -c "PATH=$PATH bash kind/setup_kind_cluster.sh")
fi

# Memory limits are per container: they survive restarts but not a recreated cluster.
for node in $(kind get nodes); do
  dockr update --memory "$NODE_MEMORY" --memory-swap "$NODE_MEMORY" "$node" >/dev/null
done

dockr stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}" $(kind get nodes)
kubectl get nodes
