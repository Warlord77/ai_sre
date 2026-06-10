#!/usr/bin/env bash
# ralph.sh -- run agent-box headless in a loop until the task is done (or max iters).
#
# Cleaner prompt input: the prompt lives in a FILE and is piped in on stdin, so
# you never cram a long prompt + flags onto one command line (and the "no stdin
# data" warning disappears, because stdin actually has data).
#
# The loop is the "ralph" pattern: the agent does ONE unit of work per run, and
# the wrapper keeps re-running it -- feeding the same prompt plus fresh git
# context each round -- until the agent signals completion or we hit --max.
#
# Stop signal: the agent prints <promise>NO MORE TASKS</promise> when the backlog
# is empty (the prompt file instructs it to). Matches the Ralph reference pattern.
#
# Usage (run from the repo you want the agent to work on):
#   cd ~/work/my-app
#   /path/to/agent-box/scripts/ralph.sh                 # ./ralph/prompt.md, up to 5 runs
#   /path/to/agent-box/scripts/ralph.sh -p task.md -n 10
set -euo pipefail

AGENT_BOX_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROMPT_FILE="ralph/prompt.md"
MAX=5

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--prompt) PROMPT_FILE="$2"; shift 2 ;;
    -n|--max)    MAX="$2"; shift 2 ;;
    -h|--help)   sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "ralph: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

[[ -f "$PROMPT_FILE" ]] || { echo "ralph: prompt file not found: $PROMPT_FILE" >&2; exit 1; }

iter=0
tmp_out="$(mktemp)"
trap 'rm -f "$tmp_out"' EXIT

while (( iter < MAX )); do
  iter=$((iter + 1))
  echo ""
  echo "════════════════  ralph run ${iter} of ${MAX}  ════════════════"

  # Build this run's input: the task prompt + a little fresh git context, so the
  # agent can see what it (or you) changed since last run. Piped in on stdin.
  {
    cat "$PROMPT_FILE"
    if git rev-parse --git-dir >/dev/null 2>&1; then
      echo ""
      echo "--- recent commits ---"
      git log -n 5 --oneline 2>/dev/null || true
      echo "--- uncommitted changes ---"
      git status --short 2>/dev/null || true
    fi
  } | "$AGENT_BOX_DIR/scripts/headless.sh" \
        --print --dangerously-skip-permissions \
      | tee "$tmp_out"

  if grep -q "NO MORE TASKS" "$tmp_out"; then
    echo ""
    echo "──── agent signalled NO MORE TASKS -- stopping after ${iter} run(s) ────"
    break
  fi
done

echo ""
echo "════════════════  ralph finished: ${iter} run(s)  ════════════════"
