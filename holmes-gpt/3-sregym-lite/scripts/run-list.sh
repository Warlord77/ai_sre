#!/usr/bin/env bash
# Run SREGym problems one at a time (each a separate `make run-one`), continuing past failures.
# Usage: scripts/run-list.sh <problem_id>...
cd "$(dirname "$0")/.."
for p in "$@"; do
  echo "=== $(date '+%H:%M') starting $p"
  make run-one PROBLEM="$p" || echo "=== $p exited non-zero"
done
echo "=== run-list finished"
