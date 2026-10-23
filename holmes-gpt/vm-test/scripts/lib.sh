# Shared helpers, sourced by the other scripts.
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export PATH="$HOME/.local/bin:$PATH"

if [[ -f "$HERE/.env" ]]; then
  set -a; . "$HERE/.env"; set +a
fi

SREGYM_DIR=${SREGYM_DIR:-../../../SREGym}
SREGYM_ABS=$(cd "$HERE" && cd "$SREGYM_DIR" 2>/dev/null && pwd || echo "$HERE/$SREGYM_DIR")
HOLMES_IMAGE=${HOLMES_IMAGE:-us-central1-docker.pkg.dev/genuine-flight-317411/devel/holmes:latest}

# Run docker even when this shell predates the user's docker group membership.
dockr() {
  if docker info >/dev/null 2>&1; then
    docker "$@"
  else
    sg docker -c "$(printf '%q ' docker "$@")"
  fi
}

# curl against the model endpoint, resolving its host to the tunnel when HOLMES_EXTRA_HOSTS maps it.
model_curl() {
  local resolve=() host port
  host=$(sed -E 's#^https?://([^:/]+).*#\1#' <<<"$OPENAI_API_BASE")
  port=$(sed -nE 's#^https?://[^:/]+:([0-9]+).*#\1#p' <<<"$OPENAI_API_BASE")
  for pair in ${HOLMES_EXTRA_HOSTS:-}; do
    [[ ${pair%%:*} == "$host" ]] && resolve=(--resolve "$host:${port:-443}:${pair#*:}")
  done
  curl -sS "${resolve[@]}" -H "Authorization: Bearer $OPENAI_API_KEY" "$@"
}

ok()   { echo "  ✅ $*"; }
fail() { echo "  ❌ $*"; exit 1; }
