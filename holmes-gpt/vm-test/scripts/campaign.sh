#!/usr/bin/env bash
# Runs problems back to back with `make record-run`, one at a time.
# Before each problem it waits (up to MODEL_WAIT seconds) for the model endpoint, so a
# dropped tunnel pauses the campaign instead of failing a problem at preflight.
# Progress lines go to logs/campaign.log: START / DONE <exit> / SKIP <reason>.
# Usage: scripts/campaign.sh <problem_id>...
set -uo pipefail
source "$(dirname "$0")/lib.sh"
cd "$HERE"
LOG=$HERE/logs/campaign.log
MODEL_WAIT=${MODEL_WAIT:-1800}
mkdir -p logs

say() { echo "$(date '+%H:%M:%S') $*" | tee -a "$LOG"; }

# Don't start while another SREGym run is still going (e.g. one launched by hand).
while pgrep -f 'main.py --agent holmesgpt' >/dev/null; do sleep 15; done

for p in "$@"; do
  waited=0
  until bash scripts/check-model.sh >/dev/null 2>&1; do
    (( waited == 0 )) && say "WAIT model unreachable before $p"
    (( waited >= MODEL_WAIT )) && break
    sleep 30; waited=$((waited + 30))
  done
  if (( waited >= MODEL_WAIT )); then
    say "SKIP $p (model unreachable for ${MODEL_WAIT}s)"; continue
  fi
  say "START $p"
  make record-run PROBLEM="$p" >/dev/null 2>&1
  say "DONE $p exit=$?"
done
say "CAMPAIGN FINISHED"
