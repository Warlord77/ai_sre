#!/usr/bin/env bash
# Copies a problem's execution logs from SREGym into results/<problem>/ and renders
# HolmesGPT's answer as an image for the README.
#   sregym.log        SREGym conductor log for the run
#   holmes.log/.json  HolmesGPT CLI transcript and JSON output (tool calls, tokens, answer)
#   judge.csv         SREGym's result row (judge verdict, scores, checklist, timings)
#   run.log           `make run-one` output
#   answer.md         HolmesGPT's final answer
# Usage: scripts/collect-results.sh <problem_id> [sregym-results-dir]
set -euo pipefail
source "$(dirname "$0")/lib.sh"

P=$1
SRC=${2:-$(ls -td "$SREGYM_ABS"/results/*/holmesgpt/"$P" 2>/dev/null | head -1)}
[[ -d $SRC ]] || fail "no SREGym results for $P"
RUN=$(ls -td "$SRC"/run_* | head -1)
OUT=$HERE/results/$P
mkdir -p "$OUT"

cp "$(ls -t "$RUN"/holmes_*.log | head -1)" "$OUT/holmes.log"
cp "$(ls -t "$RUN"/holmes_*.json | head -1)" "$OUT/holmes.json"
cp "$(ls -t "$RUN"/sregym_*.log | head -1)" "$OUT/sregym.log"
cp "$RUN/${P}_results.csv" "$OUT/judge.csv"
[[ -f $HERE/logs/run-$P.log ]] && cp "$HERE/logs/run-$P.log" "$OUT/run.log"
python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("result") or "")' "$OUT/holmes.json" > "$OUT/answer.md"

# Logs hold full command lines and environments: never keep the API key.
[[ -n ${OPENAI_API_KEY:-} ]] && sed -i "s/${OPENAI_API_KEY}/<redacted>/g" "$OUT"/*

# Image of the answer's root-cause section plus the judge's verdict, for the README.
python3 - "$OUT" > "$OUT/summary.txt" <<'EOF'
import csv, json, sys, textwrap
out = sys.argv[1]
row = next(csv.DictReader(open(f"{out}/judge.csv")))
h = json.load(open(f"{out}/holmes.json"))
ans = h.get("result") or ""
i = ans.lower().rfind("root cause")
body = ans[i:] if i >= 0 else ans
print(f"$ problem: {row['problem_id']}")
print(f"$ holmesgpt: {len(h.get('tool_calls', []))} tool calls, {h.get('num_llm_calls')} LLM calls, "
      f"{h.get('total_tokens'):,} tokens, {float(row['phase.stage:diagnosis.duration_s'])/60:.1f} min")
print()
for line in body.splitlines()[:28]:
    print(textwrap.shorten(line, 135, placeholder=" …") if line.strip() else "")
print()
print(f"$ judge: success={row['Diagnosis.success']}  score={row['Diagnosis.accuracy']}/100")
print(textwrap.fill(row["Diagnosis.reasoning"][:400], 135))
EOF
COLS=140 ROWS=$(( $(wc -l < "$OUT/summary.txt") + 2 )) bash "$HERE/scripts/record.sh" "answer-$P" cat "$OUT/summary.txt" >/dev/null
rm -f "$HERE/recordings/answer-$P".{cast,gif}
ok "collected $P → results/$P/ and docs/img/answer-$P.png"
