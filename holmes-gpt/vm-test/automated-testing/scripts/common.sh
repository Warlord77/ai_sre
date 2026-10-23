# Sourced by every script: loads .env, resolves the provider into LiteLLM model strings.
AT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export PATH="$HOME/.local/bin:$PATH"

[[ -f "$AT/.env" ]] || { echo "No .env: cp .env.example .env and fill in one provider"; exit 1; }
set -a; . "$AT/.env"; set +a

SREGYM_ABS=$(cd "$AT" && cd "${SREGYM_DIR:-../../../../SREGym}" 2>/dev/null && pwd) \
  || { echo "SREGym not found at SREGYM_DIR=${SREGYM_DIR}"; exit 1; }
DRIVER_DIR=$(cd "$AT/../client/holmesgpt" && pwd)
export SREGYM_ROOT=$SREGYM_ABS
export HOLMES_IMAGE=${HOLMES_IMAGE:-us-central1-docker.pkg.dev/genuine-flight-317411/devel/holmes:latest}
# Host network: SREGym's K8s proxy, MCP port-forward and any SSH tunnel all listen on 127.0.0.1.
export HOLMES_NETWORK=host HOLMES_MEMORY=${HOLMES_MEMORY:-1g} HOLMES_MAX_STEPS=${HOLMES_MAX_STEPS:-60}

# Export only the selected provider's credentials, so the driver forwards nothing else.
case ${PROVIDER:-} in
  selfhosted)
    [[ -n ${OPENAI_API_BASE:-} && -n ${OPENAI_API_KEY:-} && -n ${SELFHOSTED_MODEL:-} ]] \
      || { echo "PROVIDER=selfhosted needs OPENAI_API_BASE, OPENAI_API_KEY, SELFHOSTED_MODEL"; exit 1; }
    MODEL=openai/$SELFHOSTED_MODEL
    unset ANTHROPIC_API_KEY OPENROUTER_API_KEY ;;
  claude)
    [[ -n ${ANTHROPIC_API_KEY:-} ]] || { echo "PROVIDER=claude needs ANTHROPIC_API_KEY"; exit 1; }
    MODEL=anthropic/${CLAUDE_MODEL:-claude-opus-5-5}
    unset OPENAI_API_BASE OPENAI_API_KEY OPENROUTER_API_KEY HOLMES_EXTRA_HOSTS ;;
  openrouter)
    [[ -n ${OPENROUTER_API_KEY:-} ]] || { echo "PROVIDER=openrouter needs OPENROUTER_API_KEY"; exit 1; }
    MODEL=openrouter/${OPENROUTER_MODEL:-anthropic/claude-opus-5.5}
    unset OPENAI_API_BASE OPENAI_API_KEY ANTHROPIC_API_KEY HOLMES_EXTRA_HOSTS ;;
  *) echo "PROVIDER must be selfhosted, claude or openrouter (got '${PROVIDER:-}')"; exit 1 ;;
esac
JUDGE_MODEL=${JUDGE_MODEL:-$MODEL}
export MODEL JUDGE_MODEL

ok()   { echo "  ✅ $*"; }
fail() { echo "  ❌ $*"; exit 1; }

dockr() {
  if docker info >/dev/null 2>&1; then docker "$@"; else sg docker -c "$(printf '%q ' docker "$@")"; fi
}
# kind talks to Docker too: without docker-group access `kind get clusters` prints nothing.
kindc() {
  if docker info >/dev/null 2>&1; then kind "$@"; else sg docker -c "PATH=$PATH $(printf '%q ' kind "$@")"; fi
}

# SREGym-Lite problem ids, in suite order, straight from SREGym.
lite_problems() {
  (cd "$SREGYM_ABS" && .venv/bin/python -c \
    'from sregym.conductor.problem_sets import SREGYM_LITE_PROBLEMS as P; print("\n".join(P))')
}

# Resolve "3", "3,5,7", "1-4", "all" or problem ids into ids.
resolve_problems() {
  mapfile -t ALL < <(lite_problems)
  local out=() tok
  for tok in ${*//,/ }; do
    if [[ $tok == all ]]; then out+=("${ALL[@]}")
    elif [[ $tok =~ ^([0-9]+)-([0-9]+)$ ]]; then
      for ((i = BASH_REMATCH[1]; i <= BASH_REMATCH[2]; i++)); do out+=("${ALL[i-1]}"); done
    elif [[ $tok =~ ^[0-9]+$ ]]; then out+=("${ALL[tok-1]}")
    else printf '%s\n' "${ALL[@]}" | grep -qx "$tok" || { echo "unknown problem: $tok" >&2; return 1; }; out+=("$tok")
    fi
  done
  printf '%s\n' "${out[@]}"
}

sregym_busy() { pgrep -f 'main[.]py --agent holmesgpt' >/dev/null; }
