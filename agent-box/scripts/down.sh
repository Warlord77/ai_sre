#!/usr/bin/env bash
set -euo pipefail

# Force-removes all agent-box containers + images. Idempotent.
# Use -f throughout: containers may be in any state (running/exited/stuck),
# and images may have dangling references that block plain rmi.

# ── Colors (disabled when not a TTY) ─────────────────────────────────────────
if [[ -t 1 ]]; then
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  RED='\033[0;31m'
  DIM='\033[2m'
  NC='\033[0m'
else
  GREEN='' YELLOW='' RED='' DIM='' NC=''
fi

# ── Containers ───────────────────────────────────────────────────────────────
# Match by image name. `docker ps --filter ancestor=NAME` requires the full
# image:tag (a bare NAME silently means NAME:latest, which we never tag),
# so we list all containers and filter the image column via awk.
#
# The regex catches both our base images (agent-box-hermes / agent-box-claude)
# AND devcontainer's UID-remap wrapper images (vsc-agent-box-<hash>-uid), which
# the devcontainer CLI builds whenever updateRemoteUserUID is true and the host
# UID differs from the image UID -- common in CI runners.
CONTAINERS=$(docker ps -a --format '{{.ID}} {{.Image}}' 2>/dev/null \
  | awk '$2 ~ /(^|-)agent-box(-|:|$)/ {print $1}' \
  || true)

if [ -n "$CONTAINERS" ]; then
  echo -e "${DIM}==>${NC} removing containers..."
  if docker rm -f $CONTAINERS > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}  containers removed"
  else
    echo -e "${RED}!${NC}  some containers could not be removed"
  fi
else
  echo -e "${DIM}==>${NC} no containers to remove"
fi

# ── Images ───────────────────────────────────────────────────────────────────
# docker images -q accepts only ONE repository argument, so we list all images
# and filter the repository column via awk (same pattern as containers above,
# also catches devcontainer's vsc-agent-box-<hash>-uid wrappers).
IMAGES=$(docker images --format '{{.ID}} {{.Repository}}' 2>/dev/null \
  | awk '$2 ~ /(^|-)agent-box(-|:|$)/ {print $1}' \
  | sort -u \
  || true)

if [ -n "$IMAGES" ]; then
  echo -e "${DIM}==>${NC} removing images..."
  if docker rmi -f $IMAGES > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}  images removed"
  else
    echo -e "${RED}!${NC}  some images could not be removed"
  fi
else
  echo -e "${DIM}==>${NC} no images to remove"
fi

echo -e "${GREEN}✓${NC}  agent-box cleaned up"
