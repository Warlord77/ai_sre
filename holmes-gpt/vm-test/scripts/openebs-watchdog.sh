#!/usr/bin/env bash
# Unsticks OpenEBS local-PV provisioning during SREGym runs.
#
# When the provisioner restarts mid-provision (it loses its leader lease while the API server
# is busy with a deploy), its finished init-pvc-* helper pods are left behind and every retry
# fails with: pods "init-pvc-..." already exists. PVCs stay Pending and MongoDB pods never schedule.
# Fix: delete the Completed helpers, then restart the provisioner to skip its retry backoff.
#
# Usage: scripts/openebs-watchdog.sh [interval-seconds]   (Ctrl-C to stop)
set -uo pipefail
source "$(dirname "$0")/lib.sh"
INTERVAL=${1:-30}

while true; do
  # Helpers that finished over 2 minutes ago: a healthy provisioner deletes them within seconds.
  cutoff=$(date -u -d '-2 min' +%Y-%m-%dT%H:%M:%SZ)
  stale=$(kubectl -n openebs get pods -o jsonpath='{range .items[*]}{.metadata.name} {.status.phase} {.status.containerStatuses[0].state.terminated.finishedAt}{"\n"}{end}' 2>/dev/null \
    | awk -v c="$cutoff" '$1 ~ /^init-pvc-/ && $2 == "Succeeded" && $3 != "" && $3 < c {print $1}')
  stuck=$(kubectl get events -A --field-selector reason=ProvisioningFailed -o jsonpath='{range .items[*]}{.message}{"\n"}{end}' 2>/dev/null \
    | grep -c 'init-pvc-.*already exists' || true)
  if [[ -n $stale && $stuck -gt 0 ]]; then
    echo "$(date '+%H:%M:%S') stuck provisioning: deleting $(wc -w <<<"$stale") stale helper pod(s), restarting provisioner"
    kubectl -n openebs delete pod $stale --wait=false >/dev/null
    kubectl -n openebs rollout restart deploy/openebs-localpv-provisioner >/dev/null
    # Old events keep matching for a while; give the provisioner time before checking again.
    sleep 120
  fi
  sleep "$INTERVAL"
done
