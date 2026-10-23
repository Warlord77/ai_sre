"""Fill a finished problem into README.md: per-problem row, observation row, scorecard; then rebuild
the Execution section (scripts/readme-exec.py).
Usage: python3 scripts/readme-add.py <problem> <status> "<notes>" "<ground truth>" "<concluded>" "<why>"
       python3 scripts/readme-add.py --scorecard   (recompute the scorecard only)
"""
import csv, json, re, sys
from pathlib import Path

here = Path(__file__).resolve().parent.parent
readme = here / "README.md"
s = readme.read_text()
SCORECARD_ONLY = sys.argv[1:] == ["--scorecard"]
if not SCORECARD_ONLY:
    p, status, notes, truth, concluded, why = sys.argv[1:7]

if not SCORECARD_ONLY:
    row = next(csv.DictReader(open(here / f"results/{p}/judge.csv")))
    score = float(row["Diagnosis.accuracy"])
    mins = float(row["phase.stage:diagnosis.duration_s"]) / 60

    # Per-problem row
    pat = re.compile(rf"^\| (\d+) \| `{re.escape(p)}` \| [^\n]*$", re.M)
    m = pat.search(s)
    num = m.group(1)
    s = s[: m.start()] + f"| {num} | `{p}` | {status} | {score:.0f} | {mins:.1f} min | {notes} |" + s[m.end():]

    # Observation row: insert in problem order
    obs_hdr = "| # | Problem | Ground truth | What HolmesGPT concluded | Why it passed / missed |\n|---|---------|--------------|--------------------------|------------------------|\n"
    i = s.index(obs_hdr) + len(obs_hdr)
    j = s.index("\n\n", i - 1)
    rows = [r for r in s[i:j].split("\n") if r.strip() and not r.startswith(f"| {num} | `{p}`")]
    rows.append(f"| {num} | `{p}` | {truth} | {concluded} | {why} |")
    rows.sort(key=lambda r: int(r.split("|")[1]))
    s = s[:i] + "\n".join(rows) + s[j:]


# Scorecard from the per-problem table
graded, passed, failed, invalid, scores, times = 0, 0, 0, 0, [], []
for r in re.finditer(r"^\| \d+ \| `[^`]+` \|\s*([^|]+?)\s*\|\s*([^|]*?)\s*\|\s*([^|]*?)\s*\|", s, re.M):
    st, sc, t = (x.strip() for x in r.groups())
    if st.startswith("✅"): passed += 1
    elif st.startswith("❌"): failed += 1
    elif st.startswith("⚠️"): invalid += 1
    else: continue
    if not st.startswith("⚠️") and sc: scores.append(float(sc)); times.append(float(t.split()[0]))
run = passed + failed + invalid
graded = passed + failed
rate = f"{100 * passed / graded:.0f}%" if graded else "—"
avg = f"{sum(scores) / len(scores):.0f}/100" if scores else "—"
avgt = f"{sum(times) / len(times):.1f} min" if times else "—"
s = re.sub(r"^\| \d+/17 \| .*$", f"| {run}/17 | {passed} | {failed} | {invalid} | {rate} | {avg} | {avgt} |", s, count=1, flags=re.M)
readme.write_text(s)
print(f"README: {'scorecard' if SCORECARD_ONLY else p + ' → ' + status + f', {score:.0f}/100'}; scorecard {run}/17, {passed} passed, avg {avg}")

import subprocess
subprocess.run([sys.executable, str(here / "scripts/readme-exec.py")], check=True)
