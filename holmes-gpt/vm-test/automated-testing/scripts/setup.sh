#!/usr/bin/env bash
# One-shot setup: tools, cluster, SREGym, HolmesGPT image, model check, driver registration.
# Safe to re-run; each step is skipped when already done.
set -euo pipefail
source "$(dirname "$0")/common.sh"
STEP=${1:-all}

step_tools() {
  echo "== tools"
  for t in docker kind kubectl helm uv; do
    command -v $t >/dev/null && ok "$t" || fail "$t missing: run '../scripts/02-install-tools.sh' (docker: sudo bash ../scripts/01-install-docker.sh)"
  done
  dockr info >/dev/null 2>&1 && ok "docker daemon reachable" || fail "docker daemon not reachable"
}

step_cluster() {
  echo "== cluster"
  local clusters
  clusters=$(kindc get clusters 2>&1) || fail "cannot query kind: $clusters"
  if ! grep -qx kind <<<"$clusters"; then
    echo "  creating SREGym kind cluster (4 nodes, Calico)..."
    bash "$AT/../scripts/03-create-cluster.sh"
  fi
  kubectl config use-context "${KUBE_CONTEXT:-kind-kind}" >/dev/null
  kubectl get nodes --no-headers | awk '{print "  " $1, $2}'
  [[ $(kubectl get nodes --no-headers | grep -vc ' Ready') -eq 0 ]] && ok "all nodes Ready" || fail "nodes not Ready"
}

step_sregym() {
  echo "== SREGym ($SREGYM_ABS)"
  [[ -d $SREGYM_ABS/.venv ]] || bash "$AT/../scripts/04-setup-sregym.sh"
  [[ -n $(ls -A "$SREGYM_ABS/SREGym-applications" 2>/dev/null) ]] || (cd "$SREGYM_ABS" && git submodule update --init --recursive)
  ok "SREGym $(cd "$SREGYM_ABS" && git log -1 --format=%h) with $(lite_problems | wc -l) SREGym-Lite problems"
}

step_holmes() {
  echo "== HolmesGPT image"
  dockr image inspect "$HOLMES_IMAGE" >/dev/null 2>&1 || dockr pull "$HOLMES_IMAGE" | tail -1
  ok "holmes $(dockr run --rm "$HOLMES_IMAGE" version 2>/dev/null | tail -1)"
}

step_model() {
  echo "== model ($PROVIDER)"
  "$SREGYM_ABS/.venv/bin/python" "$AT/scripts/check-model.py" "$MODEL"
  [[ $JUDGE_MODEL == "$MODEL" ]] || "$SREGYM_ABS/.venv/bin/python" "$AT/scripts/check-model.py" "$JUDGE_MODEL"
}

step_install() {
  echo "== driver"
  ln -sfn "$DRIVER_DIR" "$SREGYM_ABS/clients/holmesgpt"
  grep -q 'name: holmesgpt' "$SREGYM_ABS/agents.yaml" || printf '%s\n' \
    '  - name: holmesgpt' \
    '    kickoff_command: python -m clients.holmesgpt.driver' \
    '    kickoff_workdir: .' \
    '    kickoff_env: null' \
    '    install_script: null' \
    '    agent_version: null' \
    '    container_isolation: false' >> "$SREGYM_ABS/agents.yaml"
  ok "SREGym/clients/holmesgpt → $DRIVER_DIR; agent 'holmesgpt' registered"
}

case $STEP in
  all) step_tools; step_cluster; step_sregym; step_holmes; step_model; step_install ;;
  *) "step_$STEP" ;;
esac
echo "Ready: provider=$PROVIDER agent=$MODEL judge=$JUDGE_MODEL"
