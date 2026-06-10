#!/usr/bin/env bash
# headless.sh -- run Claude Code in agent-box non-interactively.
#
# All args after the script name are forwarded directly to `claude` inside
# the container. The current working directory is mounted as /workspace.
# The same isolation primitives as the interactive REPL apply: cap-drop=ALL,
# no-new-privileges, non-root user, no host credential mounts.
#
# Usage (from any project dir):
#   /path/to/agent-box/scripts/headless.sh [claude args...]
#
# Example -- single-shot inside a target repo:
#   cd ~/work/my-app
#   ~/agent-box/scripts/headless.sh \
#     --print --output-format stream-json \
#     --model claude-opus-4-7 \
#     --dangerously-skip-permissions \
#     "Fix the failing test in src/auth.test.ts"
#
# Example -- inside an AFK loop (ralph-style wrapper):
#   commits=$(git log -n 5 --format="%B---")
#   issues=$(cat issues/*.md)
#   ~/agent-box/scripts/headless.sh \
#     --verbose --print --output-format stream-json \
#     --model claude-opus-4-7 --dangerously-skip-permissions \
#     "Commits: $commits | Issues: $issues | $(cat ralph/prompt.md)"

set -euo pipefail

AGENT_BOX_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DC_DIR="$AGENT_BOX_DIR/.devcontainer"
AGENT_IMAGE="agent-box-claude"

# ── Build image on first run ─────────────────────────────────────────────────
# Reuses the agent-box Dockerfile. If no tag exists yet, build a fresh one.
if ! docker images --format '{{.Repository}}' "$AGENT_IMAGE" 2>/dev/null | grep -q .; then
  TAG=$(date +%Y%m%d-%H%M%S)
  echo "==> building ${AGENT_IMAGE}:${TAG} (first run -- ~3 min)" >&2
  docker build --target claude \
    -t "${AGENT_IMAGE}:${TAG}" \
    -t "${AGENT_IMAGE}:latest" \
    -f "$DC_DIR/Dockerfile" "$AGENT_BOX_DIR/"
fi

# Pick the most recent tag if `latest` doesn't exist (first build before re-tag)
TAG=$(docker images --format '{{.Tag}}' "$AGENT_IMAGE" 2>/dev/null | sort -r | head -1)
if [[ -z "$TAG" ]]; then
  echo "error: $AGENT_IMAGE image not found and build failed" >&2
  exit 1
fi

# ── Load auth from agent-box .env (CLAUDE_CODE_OAUTH_TOKEN / ANTHROPIC_API_KEY)
# Headless mode runs from anywhere, but auth always comes from agent-box/.env.
if [[ -f "$AGENT_BOX_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$AGENT_BOX_DIR/.env"
  set +a
fi

# ── Run Claude inside agent-box ──────────────────────────────────────────────
# - --rm: remove container after exit (one-shot)
# - -i: keep stdin open (needed for stream-json mode)
# - cap-drop + no-new-privs: same isolation as interactive REPL
# - $PWD mounted as /workspace: agent writes happen in the caller's dir
# - all args after "claude" forwarded to the Claude Code CLI
exec docker run --rm -i \
  --cap-drop=ALL \
  --security-opt no-new-privileges \
  -v "$PWD:/workspace" \
  -w /workspace \
  -e CLAUDE_CODE_OAUTH_TOKEN \
  -e ANTHROPIC_API_KEY \
  "${AGENT_IMAGE}:${TAG}" \
  claude "$@"
