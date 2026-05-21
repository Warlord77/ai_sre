#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"

CONTAINER_ID=$(devcontainer up --workspace-folder "$WORKSPACE" 2>/dev/null | grep '^{' | jq -r '.containerId')

docker exec "$CONTAINER_ID" bash -c 'echo "claude auth login" > /tmp/.autorun'

HEX=$(printf '%s' "$CONTAINER_ID" | xxd -p | tr -d '\n')
code --new-window --folder-uri "vscode-remote://attached-container+${HEX}/workspace"

osascript \
    -e 'delay 1' \
    -e 'tell application "Visual Studio Code" to activate' \
    -e 'tell application "System Events" to key code 50 using {control down}'
