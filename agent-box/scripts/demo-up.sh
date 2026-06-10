#!/usr/bin/env bash
# demo-up.sh -- seed a throwaway repo for a BRIEF-DRIVEN ralph run.
#
# A human writes ONE thing: BRIEF.md (the high-level ask). The loop does the rest:
#   run 1  -> architect skill: read BRIEF.md, write the ADR, and WRITE the task list
#             into issues/ (one file per task) so the backlog is visible.
#   run 2+ -> backend-dev skill: implement one issue (TDD), commit, move it to done/.
#   end    -> <promise>NO MORE TASKS</promise>.
# Disposable: `make demo-down` deletes it. Agent commits land HERE, never in ai-bites.
# Zero deps: tests run on Node 20's built-in `node --test`.
set -euo pipefail

DEST="${1:?usage: demo-up.sh <dir>}"
AGENT_BOX_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -e "$DEST" ]]; then
  echo "demo dir already exists: $DEST" >&2
  echo "run 'make demo-down' (from agent-box/) first for a fresh one." >&2
  exit 1
fi

mkdir -p "$DEST/src" "$DEST/ralph/issues/done"
cd "$DEST"

# ── the codebase: an empty stub the agent will design + fill ─────────────────
cat > package.json <<'JSON'
{
  "name": "calc-demo",
  "version": "0.0.0",
  "type": "module",
  "scripts": {
    "test": "node --test",
    "typecheck": "node --check src/calc.mjs"
  }
}
JSON

cat > src/calc.mjs <<'JS'
// calc -- implement per BRIEF.md and the issues/ the architect writes.
JS

cat > .gitignore <<'GI'
node_modules/
GI

# keep the (initially empty) backlog dirs in git so they're visible from the start
touch ralph/issues/.gitkeep ralph/issues/done/.gitkeep

# ── the ONLY human-authored input: the high-level brief ──────────────────────
cat > BRIEF.md <<'MD'
# Brief: a small calculator module

Build a tiny calculator library in `src/calc.mjs` exposing the basic arithmetic
operations (add, subtract, multiply, divide). Decide and document how divide-by-zero
should behave. Ship it test-first.

Out of scope: CLI, UI, persistence. Keep it a pure module.
MD

# ── the operating manual the loop feeds the agent every run ──────────────────
# Kept as a standalone, showable file at agent-box/ralph/prompt.md; copied in here.
cp "$AGENT_BOX_DIR/ralph/prompt.md" ralph/prompt.md

# ── throwaway repo; local identity so agent commits aren't attributed to you ──
git init -q
git config user.name  'ralph-agent'
git config user.email 'ralph@agent-box.local'
git add -A
git commit -qm "seed: calc project + BRIEF.md (issues/ empty -- the agent fills it)"

# The container's baked agent user is uid 1000. On Linux a bind-mounted dir keeps the
# host owner's uid, so the agent can't write it (macOS papers over this; CI does not).
# This repo is throwaway -- make it writable by any uid so the agent can do its work.
chmod -R o+rwX "$DEST"

echo "seeded throwaway demo repo: $DEST"
echo "  human input: BRIEF.md   |   ralph/issues/: empty (the architect run will fill it)"
echo
echo "from agent-box/, all short + portable:"
echo "  make demo-run                 # run the loop (override cap: make demo-run N=10)"
echo "  ls .demo/ralph/issues         # the issues the agent WROTE from the brief"
echo "  git -C .demo --no-pager log --oneline   # the commit trail"
echo "  make demo-verify              # run the tests in the box"
echo "  make demo-down                # clean up"
