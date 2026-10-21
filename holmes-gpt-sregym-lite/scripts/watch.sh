#!/usr/bin/env bash
# Regenerate README.md's results block after every finished SREGym problem and
# commit the experiment folder to the ai_sre repo (local commit, no push).
# Exits when the run ends.
# Usage: scripts/watch.sh <sregym-dir> <run-dir-name>...   (a resumed campaign spans several)
#        scripts/watch.sh <sregym-dir> since:<run-dir-name>  (every run dir from that one on)
set -euo pipefail

SREGYM=$1; shift
RUNS=("$@")
[ ${#RUNS[@]} -gt 0 ] || RUNS=("$(ls -t "$SREGYM/results" | grep -E '^[0-9]{4}_[0-9]{4}$' | head -1)")
HERE=$(cd "$(dirname "$0")/.." && pwd)
SINCE=""
[[ ${RUNS[0]} == since:* ]] && SINCE=${RUNS[0]#since:}
refresh_runs() {
  [ -n "$SINCE" ] || return 0
  RUNS=()
  for d in $(ls "$SREGYM/results" | grep -E '^[0-9]{4}_[0-9]{4}$' | sort); do [[ ! $d < $SINCE ]] && RUNS+=("$d"); done
}
refresh_runs
echo "watching ${RUNS[*]}"

update() {
  line=$(python3 "$HERE/scripts/summarize.py" --sregym "$SREGYM" --run "${RUNS[@]}" --out "$HERE/results" \
    --readme "$HERE/README.md" --root-readme "$HERE/../README.md" | head -1)
  git -C "$HERE" add README.md Makefile .gitignore .env.example invalid.txt skip.txt client scripts results ../README.md
  if ! git -C "$HERE" diff --cached --quiet -- . ../README.md; then
    git -C "$HERE" commit -q -m "holmesgpt sregym-lite: results after $1 finished problems" \
      -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- . ../README.md
  fi
  echo "$(date '+%H:%M') updated README ($1 problems done) — $line"
}

count() {
  for r in "${RUNS[@]}"; do
    find "$SREGYM/results/$r/holmesgpt" -name '*_holmesgpt_results.csv' ! -name '_running_*' 2>/dev/null
  done | xargs -n1 basename 2>/dev/null | sort -u | wc -l | tr -d ' '
}

last=-1
while :; do
  refresh_runs
  n=$(count)
  if [ "$n" != "$last" ]; then update "$n"; last=$n; fi
  pgrep -f "main.py --agent holmesgpt|scripts/run-list.sh" >/dev/null || { update "$(count)"; echo "run finished"; break; }
  sleep 30
done
