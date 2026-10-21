#!/usr/bin/env bash
# Regenerate README.md's results block after every finished SREGym problem and
# commit the experiment folder to the ai_sre repo (local commit, no push).
# Exits when the run ends.
# Usage: scripts/watch.sh <sregym-dir> [run-dir-name]
set -euo pipefail

SREGYM=$1
RUN=${2:-$(ls -t "$SREGYM/results" | grep -E '^[0-9]{4}_[0-9]{4}$' | head -1)}
HERE=$(cd "$(dirname "$0")/.." && pwd)
echo "watching $SREGYM/results/$RUN"

update() {
  python3 "$HERE/scripts/summarize.py" --sregym "$SREGYM" --run "$RUN" --out "$HERE/results" --readme "$HERE/README.md" --root-readme "$HERE/../README.md" >/dev/null
  git -C "$HERE" add README.md Makefile .gitignore .env.example invalid.txt client scripts results ../README.md
  if ! git -C "$HERE" diff --cached --quiet -- . ../README.md; then
    latest=$(ls -t "$SREGYM/results/$RUN/holmesgpt" 2>/dev/null | head -1)
    git -C "$HERE" commit -q -m "holmesgpt sregym-lite: results after $1/17 problems${latest:+ ($latest)}" \
      -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- . ../README.md
  fi
  echo "$(date '+%H:%M') updated README ($1 problems done)"
}

last=-1
while :; do
  done_count=$(find "$SREGYM/results/$RUN/holmesgpt" -name '*_holmesgpt_results.csv' ! -name '_running_*' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$done_count" != "$last" ]; then
    update "$done_count"
    last=$done_count
  fi
  pgrep -f "main.py --agent holmesgpt" >/dev/null || { update "$done_count"; echo "run finished"; break; }
  sleep 30
done
