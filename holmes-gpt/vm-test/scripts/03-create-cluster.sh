#!/usr/bin/env bash
# Creates the SREGym kind cluster exactly as upstream (SREGym/kind/setup_kind_cluster.sh:
# 1 control-plane + 3 workers, SREGym node image, /run/udev mounts, Calico v3.29.3),
# then sets each node container's memory limit.
#   CONTROL_PLANE_MEMORY  default 4g
#   WORKER_MEMORY         default: host RAM, i.e. uncapped (Docker can't clear a limit once set)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

HOST_RAM=$(awk '/MemTotal/{print $2 * 1024}' /proc/meminfo)
CONTROL_PLANE_MEMORY=${CONTROL_PLANE_MEMORY:-4g}
WORKER_MEMORY=${WORKER_MEMORY:-$HOST_RAM}

# kind talks to Docker: without docker-group access `kind get clusters` prints nothing.
kindc() { sg docker -c "PATH=$PATH $(printf '%q ' kind "$@")"; }

clusters=$(kindc get clusters 2>&1) || { echo "cannot query kind: $clusters"; exit 1; }
if grep -qx kind <<<"$clusters"; then
  echo "Cluster 'kind' already exists; skipping creation (kind delete cluster --name kind to recreate)"
else
  (cd "$SREGYM_ABS" && sg docker -c "PATH=$PATH bash kind/setup_kind_cluster.sh")
fi

# Memory limits are per container: they survive restarts but not a recreated cluster.
for node in $(kindc get nodes); do
  mem=$WORKER_MEMORY
  [[ $node == *control-plane* ]] && mem=$CONTROL_PLANE_MEMORY
  dockr update --memory "$mem" --memory-swap "$mem" "$node" >/dev/null
done

dockr stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}" $(kindc get nodes)
kubectl get nodes
