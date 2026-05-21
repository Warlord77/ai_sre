#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"

CONTAINER_ID=$(devcontainer up --workspace-folder "$WORKSPACE" 2>/dev/null | grep '^{' | jq -r '.containerId')

# Configure Hermes inside the container, passing the API key and model via -e so
# they are never interpolated into the shell string (safe against values containing quotes).
docker exec \
    -e "DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY}" \
    -e "HERMES_MODEL=${HERMES_MODEL:-deepseek-v4-pro}" \
    "$CONTAINER_ID" bash -c '
    mkdir -p ~/.hermes
    printf "DEEPSEEK_API_KEY=%s\n" "$DEEPSEEK_API_KEY" > ~/.hermes/.env
    hermes config set model.provider deepseek 2>/dev/null || true
    hermes config set model.base_url https://api.deepseek.com/v1 2>/dev/null || true
    hermes config set model.default "$HERMES_MODEL" 2>/dev/null || true
'

docker exec "$CONTAINER_ID" bash -c "echo 'hermes -m ${HERMES_MODEL:-deepseek-v4-pro} chat' > /tmp/.autorun"

HEX=$(printf '%s' "$CONTAINER_ID" | xxd -p | tr -d '\n')
code --new-window --folder-uri "vscode-remote://attached-container+${HEX}/workspace"

osascript \
    -e 'delay 1' \
    -e 'tell application "Visual Studio Code" to activate' \
    -e 'tell application "System Events" to key code 50 using {control down}'
