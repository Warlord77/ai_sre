#!/usr/bin/env bash
set -euo pipefail

AGENT="${1:?usage: start.sh <agent>   e.g. start.sh hermes}"
WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
DC_DIR="$WORKSPACE/.devcontainer"
AGENTS_JSON="$DC_DIR/agents.json"
BASE_JSON="$DC_DIR/devcontainer.base.json"

OS=$(uname)

# ── Colors (disabled when not a TTY) ─────────────────────────────────────────
if [[ -t 1 ]]; then
  BOLD='\033[1m'
  DIM='\033[2m'
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  CYAN='\033[0;36m'
  NC='\033[0m'
else
  BOLD='' DIM='' RED='' GREEN='' YELLOW='' CYAN='' NC=''
fi

info()    { echo -e "${CYAN}==>${NC} ${BOLD}$*${NC}"; }
success() { echo -e "${GREEN}✓${NC}  $*"; }
warn()    { echo -e "${YELLOW}!${NC}  $*"; }
err()     { echo -e "${RED}error:${NC} $*" >&2; }
step()    { echo -e "${DIM}   $*${NC}"; }

# ── Step 1: ask how to attach ─────────────────────────────────────────────────
echo ""
MODE="terminal"
if [[ -t 0 && -t 1 ]]; then
  echo -e "${BOLD}agent-box${NC} — isolated AI coding agent sandbox"
  echo ""
  printf "${CYAN}==> ${BOLD}attach mode${NC}  ${DIM}[t]erminal${NC} / ${DIM}[v]scode${NC}  ${DIM}(default: t)${NC}: "
  read -r _mode_input
  case "$_mode_input" in
    v|V|vs|VS|vscode|VSCODE) MODE="vscode" ;;
    *) MODE="terminal" ;;
  esac
fi
echo -e "${CYAN}==> ${BOLD}mode:${NC} $MODE"
echo ""

# ── Step 2: install missing dependencies ─────────────────────────────────────
info "checking dependencies"

# docker: can't auto-install — hard fail with a clear message
if ! command -v docker &>/dev/null; then
  err "docker not found"
  if [[ "$OS" == "Darwin" ]]; then
    step "install OrbStack → orbstack.dev"
    step "or Docker Desktop → docker.com/get-started"
  else
    step "see docs.docker.com/engine/install"
  fi
  exit 1
fi
success "docker $(docker --version | awk '{print $3}' | tr -d ',')"

# jq: auto-install
if ! command -v jq &>/dev/null; then
  warn "'jq' not found — installing..."
  if [[ "$OS" == "Darwin" ]]; then
    brew install jq
  else
    sudo apt-get install -y -q jq
  fi
fi
success "jq $(jq --version)"

# devcontainer CLI: auto-install via npm if available
if ! command -v devcontainer &>/dev/null; then
  if command -v npm &>/dev/null; then
    warn "'devcontainer' CLI not found — installing via npm..."
    npm install -g @devcontainers/cli --silent
  else
    err "devcontainer CLI not found and npm is unavailable"
    if [[ "$OS" == "Darwin" ]]; then
      step "install Node.js first: brew install node"
    else
      step "install Node.js first: nodejs.org/en/download"
    fi
    step "then run: npm install -g @devcontainers/cli"
    exit 1
  fi
fi
success "devcontainer $(devcontainer --version)"

# xxd: only needed for vscode mode — macOS ships it, Linux may not
if [[ "$MODE" == "vscode" && "$OS" != "Darwin" ]] && ! command -v xxd &>/dev/null; then
  warn "'xxd' not found — installing..."
  sudo apt-get install -y -q xxd 2>/dev/null || sudo apt-get install -y -q vim-common
fi

# code CLI: required for vscode mode — fall back to terminal if missing
if [[ "$MODE" == "vscode" ]] && ! command -v code &>/dev/null; then
  warn "vscode mode selected but 'code' CLI not found"
  step "VS Code → Cmd+Shift+P → 'Shell Command: Install code in PATH'"
  warn "falling back to terminal mode"
  MODE="terminal"
fi

echo ""

# ── Step 3: bootstrap .env ────────────────────────────────────────────────────
if [[ ! -f "$WORKSPACE/.env" ]]; then
  cp "$WORKSPACE/.env.example" "$WORKSPACE/.env"
  warn "created .env from .env.example"
  step "fill in your API keys and re-run"
  exit 1
fi

# ── Step 4: validate agent name ───────────────────────────────────────────────
if ! jq -e --arg a "$AGENT" 'has($a)' "$AGENTS_JSON" > /dev/null 2>&1; then
  err "unknown agent '${AGENT}'"
  step "available: $(jq -r 'keys | join(", ")' "$AGENTS_JSON")"
  exit 1
fi

AGENT_IMAGE=$(jq -r --arg a "$AGENT" '.[$a].image' "$AGENTS_JSON")
AGENT_TARGET=$(jq -r --arg a "$AGENT" '.[$a].target' "$AGENTS_JSON")

# ── Step 5: read provider config ──────────────────────────────────────────────
PROVIDER_NAME="${HERMES_PROVIDER_NAME:-}"
PROVIDER_BASE_URL="${HERMES_PROVIDER_BASE_URL:-}"
PROVIDER_API_KEY_ENV="${HERMES_PROVIDER_API_KEY_ENV:-}"
PROVIDER_API_KEY="${PROVIDER_API_KEY_ENV:+${!PROVIDER_API_KEY_ENV:-}}"

export HERMES_MODEL="${HERMES_MODEL:-}"

# ── Resolve autorun command (needed for both devcontainer.json and /tmp/.autorun) ─
AUTORUN=$(jq -r --arg a "$AGENT" '.[$a].autorun' "$AGENTS_JSON")
if command -v perl &>/dev/null; then
  AUTORUN=$(printf '%s' "$AUTORUN" | perl -pe 's/\$\{(\w+)\}/defined $ENV{$1} ? $ENV{$1} : ""/ge; s/\$(\w+)/defined $ENV{$1} ? $ENV{$1} : ""/ge')
else
  AUTORUN="${AUTORUN//\$\{HERMES_MODEL\}/$HERMES_MODEL}"
  AUTORUN="${AUTORUN//\$HERMES_MODEL/$HERMES_MODEL}"
fi

# ── Step 6: build image if it doesn't exist ───────────────────────────────────
TAG=$(docker images --format '{{.Tag}}' "$AGENT_IMAGE" 2>/dev/null | sort -r | head -1)

if [[ -z "$TAG" ]]; then
  TAG=$(date +%Y%m%d-%H%M%S)
  info "building ${AGENT_IMAGE}:${TAG} (first run — takes ~3 min)"
  docker build --target "$AGENT_TARGET" \
    -t "${AGENT_IMAGE}:${TAG}" \
    -f "$DC_DIR/Dockerfile" "$DC_DIR/"
  success "image built"
else
  success "image found: ${AGENT_IMAGE}:${TAG}"
fi

# ── Step 7: generate devcontainer.json ────────────────────────────────────────
jq -n \
  --arg agent "$AGENT" \
  --arg image "${AGENT_IMAGE}:${TAG}" \
  --arg apiKeyEnv "$PROVIDER_API_KEY_ENV" \
  --arg mode "$MODE" \
  --arg autorun "$AUTORUN" \
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
  } * (if $mode == "vscode" then {"postAttachCommand": $autorun} else {} end)' \
  > "$DC_DIR/devcontainer.json"

# ── Step 8: stop any existing container for this workspace ────────────────────
EXISTING=$(docker ps -q --filter "label=devcontainer.local_folder=$WORKSPACE" 2>/dev/null)
if [[ -n "$EXISTING" ]]; then
  info "stopping existing container..."
  docker stop $EXISTING > /dev/null
  docker rm $EXISTING > /dev/null
fi

# ── Step 9: start the devcontainer ───────────────────────────────────────────
info "starting ${AGENT_IMAGE}..."
DC_LOG=$(mktemp)
if ! devcontainer up --workspace-folder "$WORKSPACE" > "$DC_LOG" 2>&1; then
  err "devcontainer failed to start"
  cat "$DC_LOG" >&2
  rm -f "$DC_LOG"
  exit 1
fi
CONTAINER_ID=$(grep '^{' "$DC_LOG" | jq -r '.containerId')
rm -f "$DC_LOG"

if [[ -z "$CONTAINER_ID" ]]; then
  err "devcontainer started but container ID not found"
  exit 1
fi
success "container up: ${DIM}${CONTAINER_ID:0:12}${NC}"

# ── Step 10: run agent setup inside the container ────────────────────────────
SETUP_SCRIPT=$(jq -r --arg a "$AGENT" '.[$a].setup.commands | join("\n")' "$AGENTS_JSON")

if [[ -n "$SETUP_SCRIPT" ]]; then
  env_args=()

  while IFS= read -r var; do
    [[ -z "$var" ]] && continue
    env_args+=(-e "${var}=${!var:-}")
  done < <(jq -r --arg a "$AGENT" '.[$a].setup.envPassthrough[]' "$AGENTS_JSON")

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

# ── Step 11: write autorun for terminal mode ─────────────────────────────────
# VS Code mode uses postAttachCommand in devcontainer.json instead.
if [[ "$MODE" == "terminal" ]]; then
  printf '%s\n' "$AUTORUN" | docker exec -i "$CONTAINER_ID" bash -c 'cat > /tmp/.autorun'
fi

# ── Step 12: attach based on selected mode ────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}ready${NC} — ${AGENT_IMAGE} is running"
echo ""

if [[ "$MODE" == "vscode" ]]; then
  info "opening VS Code..."
  CONTAINER_WORKSPACE=$(jq -r '.workspaceFolder' "$DC_DIR/devcontainer.json")
  if command -v xxd &>/dev/null; then
    HEX=$(printf '%s' "$CONTAINER_ID" | xxd -p | tr -d '\n')
  else
    HEX=$(printf '%s' "$CONTAINER_ID" | od -A n -t x1 | tr -d ' \n')
  fi
  code --new-window --folder-uri "vscode-remote://attached-container+${HEX}${CONTAINER_WORKSPACE}" || true
  # macOS only: bring VS Code to front; postAttachCommand in devcontainer.json opens the agent terminal
  osascript -e 'delay 2' -e 'tell application "Visual Studio Code" to activate' 2>/dev/null || true
else
  if [[ -t 0 && -t 1 ]]; then
    echo -e "${DIM}  agent starts automatically when the shell opens${NC}"
    echo -e "${DIM}  type 'exit' to leave the container${NC}"
    echo ""
    docker exec -it "$CONTAINER_ID" bash
  else
    step "container is running (non-interactive — skipping attach)"
    step "to attach: docker exec -it $CONTAINER_ID bash"
  fi
fi
