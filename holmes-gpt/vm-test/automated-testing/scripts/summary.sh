#!/usr/bin/env bash
# Prints a run's results table. Usage: scripts/summary.sh [results/<stamp>]  (default: latest run)
AT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$(ls -td "$AT"/results/*/ 2>/dev/null | head -1)}
[[ -f $OUT/summary.csv ]] || { echo "no results yet"; exit 0; }
echo "Results: ${OUT#$AT/}"
awk -F, 'BEGIN { printf "  %-55s %-8s %6s %8s\n", "problem", "verdict", "score", "minutes" }
  { printf "  %-55s %-8s %6s %8s\n", $1, $2, $3, $4; n++; if ($2 == "pass") p++; if ($2 == "pass" || $2 == "fail") { g++; s += $3 } }
  END { printf "\n  %d run, %d graded, %d passed", n, g, p; if (g) printf ", pass rate %.0f%%, avg score %.0f/100", 100 * p / g, s / g; print "" }' "$OUT/summary.csv"
