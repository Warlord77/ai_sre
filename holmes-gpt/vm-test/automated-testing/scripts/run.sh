#!/usr/bin/env bash
# Runs SREGym-Lite problems with HolmesGPT, one at a time, and collects each result.
# Usage: scripts/run.sh <selection>   e.g. 3 | 1,4,7 | 2-5 | all | network_policy_block
set -uo pipefail
source "$(dirname "$0")/common.sh"

mapfile -t PROBLEMS < <(resolve_problems "$@") || exit 1
[[ ${#PROBLEMS[@]} -gt 0 ]] || { echo "nothing selected"; exit 1; }

STAMP=$(date +%Y%m%d_%H%M)
OUT=$AT/results/$STAMP
mkdir -p "$OUT"
echo "Run $STAMP: ${#PROBLEMS[@]} problem(s), agent=$MODEL judge=$JUDGE_MODEL profile=${PROFILE:-full}"

for p in "${PROBLEMS[@]}"; do
  # SREGym owns the whole cluster per problem: never overlap with another run.
  if sregym_busy; then
    echo "  waiting: another SREGym run is in progress"
    while sregym_busy; do sleep 15; done
  fi
  "$SREGYM_ABS/.venv/bin/python" "$AT/scripts/check-model.py" "$MODEL" >/dev/null \
    || { echo "  ⚠️  $p skipped: model check failed (make check-model)"; echo "$p,skipped,model check failed" >> "$OUT/summary.csv"; continue; }

  echo "=== $(date +%T) $p"
  log=$OUT/$p.log
  (cd "$SREGYM_ABS" && uv run main.py --agent holmesgpt --model "$MODEL" --judge-model "$JUDGE_MODEL" \
     --stages diagnosis --internet-access open --profile "${PROFILE:-full}" --problem "$p") > "$log" 2>&1
  rc=$?

  src=$(grep -o 'results/[0-9_]*/holmesgpt_ALL_results.csv' "$log" | tail -1)
  run=$(ls -td "$SREGYM_ABS"/"${src%/holmesgpt_ALL_results.csv}"/holmesgpt/"$p"/run_* 2>/dev/null | head -1)
  if [[ -z $src || -z $run ]]; then
    echo "  ⚠️  no result (exit $rc), see $log"; echo "$p,error,exit $rc" >> "$OUT/summary.csv"; continue
  fi
  mkdir -p "$OUT/$p"
  cp "$run"/holmes_*.log "$run"/holmes_*.json "$run"/sregym_*.log "$run/${p}_results.csv" "$OUT/$p/" 2>/dev/null
  # Never keep provider keys in collected logs.
  for k in "${OPENAI_API_KEY:-}" "${ANTHROPIC_API_KEY:-}" "${OPENROUTER_API_KEY:-}"; do
    [[ -n $k ]] && sed -i "s|$k|<redacted>|g" "$OUT/$p"/* "$log"
  done
  "$SREGYM_ABS/.venv/bin/python" - "$OUT/$p/${p}_results.csv" "$p" >> "$OUT/summary.csv" <<'EOF'
import csv, sys
r = next(csv.DictReader(open(sys.argv[1])))
verdict = "pass" if r.get("Diagnosis.success") == "True" else ("error" if r.get("Diagnosis.judgment") == "Error" else "fail")
print(f'{sys.argv[2]},{verdict},{r.get("Diagnosis.accuracy")},{float(r.get("phase.stage:diagnosis.duration_s") or 0)/60:.1f}')
EOF
  echo "  → $(tail -1 "$OUT/summary.csv" | cut -d, -f2-) (logs: results/$STAMP/$p/)"
done
echo
bash "$AT/scripts/summary.sh" "$OUT"
