#!/usr/bin/env bash
set -euo pipefail

AGENT="${1:?usage: start.sh <agent>   e.g. start.sh hermes}"
WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
DC_DIR="$WORKSPACE/.devcontainer"
AGENTS_JSON="$DC_DIR/agents.json"
BASE_JSON="$DC_DIR/devcontainer.base.json"

# Bootstrap .env from example if missing
if [[ ! -f "$WORKSPACE/.env" ]]; then
  cp "$WORKSPACE/.env.example" "$WORKSPACE/.env"
  echo "created .env from .env.example - fill in your API keys and re-run"
  exit 1
fi

# Validate agent name against agents.json
if ! jq -e --arg a "$AGENT" 'has($a)' "$AGENTS_JSON" > /dev/null 2>&1; then
  echo "error: unknown agent '${AGENT}'"
  echo "available: $(jq -r 'keys | join(", ")' "$AGENTS_JSON")"
  exit 1
fi

AGENT_IMAGE=$(jq -r --arg a "$AGENT" '.[$a].image' "$AGENTS_JSON")
AGENT_TARGET=$(jq -r --arg a "$AGENT" '.[$a].target' "$AGENTS_JSON")

# Read provider config from environment (set in .env via Makefile export)
PROVIDER_NAME="${HERMES_PROVIDER_NAME:-}"
PROVIDER_BASE_URL="${HERMES_PROVIDER_BASE_URL:-}"
PROVIDER_API_KEY_ENV="${HERMES_PROVIDER_API_KEY_ENV:-}"
PROVIDER_API_KEY="${PROVIDER_API_KEY_ENV:+${!PROVIDER_API_KEY_ENV:-}}"

export HERMES_MODEL="${HERMES_MODEL:-}"

# Find the most recent tag for this image by querying Docker directly (no tag file needed)
TAG=$(docker images --format '{{.Tag}}' "$AGENT_IMAGE" 2>/dev/null | sort -r | head -1)

# Build if no image exists yet
if [[ -z "$TAG" ]]; then
  TAG=$(date +%Y%m%d-%H%M%S)
  echo "building ${AGENT_IMAGE}:${TAG} ..."
  docker build --target "$AGENT_TARGET" \
    -t "${AGENT_IMAGE}:${TAG}" \
    -f "$DC_DIR/Dockerfile" "$DC_DIR/"
fi

jq -n \
  --arg agent "$AGENT" \
  --arg image "${AGENT_IMAGE}:${TAG}" \
  --arg apiKeyEnv "$PROVIDER_API_KEY_ENV" \
  --slurpfile base "$BASE_JSON" \
  --slurpfile agents "$AGENTS_JSON" \
  '$base[0] * {
    "name": ("agent-box-" + $agent),
    "image": $image,
    "containerEnv": (
      $agents[0][$agent].containerEnv +
      if $apiKeyEnv != "" then
        { ($apiKeyEnv): ("${localEnv:" + $apiKeyEnv + "}") }
      else {} end
    ),
    "postCreateCommand": $agents[0][$agent].postCreateCommand,
    "customizations": {
      "vscode": {
        "extensions": $agents[0][$agent].extensions
      }
    }
  }' > "$DC_DIR/devcontainer.json"

# Start (or reuse) the devcontainer
CONTAINER_ID=$(devcontainer up --workspace-folder "$WORKSPACE" 2>/dev/null \
  | grep '^{' | jq -r '.containerId')

# Run agent-specific setup commands inside the container.
# Provider vars are injected automatically; envPassthrough covers agent-specific extras.
SETUP_SCRIPT=$(jq -r --arg a "$AGENT" '.[$a].setup.commands | join("\n")' "$AGENTS_JSON")

if [[ -n "$SETUP_SCRIPT" ]]; then
  env_args=()

  # Agent-specific env passthrough (e.g. HERMES_MODEL)
  while IFS= read -r var; do
    [[ -z "$var" ]] && continue
    env_args+=(-e "${var}=${!var:-}")
  done < <(jq -r --arg a "$AGENT" '.[$a].setup.envPassthrough[]' "$AGENTS_JSON")

  # Provider vars - passed as PROVIDER_* so setup commands stay provider-agnostic
  if [[ -n "$PROVIDER_API_KEY_ENV" ]]; then
    env_args+=(
      -e "PROVIDER_NAME=${PROVIDER_NAME}"
      -e "PROVIDER_BASE_URL=${PROVIDER_BASE_URL}"
      -e "PROVIDER_API_KEY_ENV=${PROVIDER_API_KEY_ENV}"
      -e "PROVIDER_API_KEY=${PROVIDER_API_KEY}"
    )
  fi

  docker exec ${env_args[@]+"${env_args[@]}"} "$CONTAINER_ID" bash -c "$SETUP_SCRIPT"
fi

# Write the autorun command - resolve env vars on host so container gets a literal command
AUTORUN=$(jq -r --arg a "$AGENT" '.[$a].autorun' "$AGENTS_JSON" | envsubst)
printf '%s\n' "$AUTORUN" | docker exec -i "$CONTAINER_ID" bash -c 'cat > /tmp/.autorun'

# Open VS Code attached to the running container
CONTAINER_WORKSPACE=$(jq -r '.workspaceFolder' "$DC_DIR/devcontainer.json")
HEX=$(printf '%s' "$CONTAINER_ID" | xxd -p | tr -d '\n')
code --new-window --folder-uri "vscode-remote://attached-container+${HEX}${CONTAINER_WORKSPACE}"

# macOS only: bring VS Code to front and open the integrated terminal
osascript \
    -e 'delay 2' \
    -e 'tell application "Visual Studio Code" to activate' \
    -e 'tell application "System Events" to key code 50 using {control down}' || true
