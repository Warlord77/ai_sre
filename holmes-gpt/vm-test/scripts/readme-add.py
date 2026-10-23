"""Fill a finished problem into README.md: per-problem row, observation row, execution block, scorecard.
Usage: python3 scripts/readme-add.py <problem> <status> "<notes>" "<ground truth>" "<concluded>" "<why>"
"""
import csv, json, re, sys
from pathlib import Path

here = Path(__file__).resolve().parent.parent
p, status, notes, truth, concluded, why = sys.argv[1:7]
readme = here / "README.md"
s = readme.read_text()

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

# Execution block, before the run notes
block = f"""
**{num}. `{p}`**: {status} · score {score:.0f}/100 · [logs](results/{p}/) ·
▶ [run video (GIF, 20× speed)](recordings/run-{p}.gif) · [asciinema cast](recordings/run-{p}.cast)

![problem {num}: HolmesGPT answer and judge verdict](docs/img/answer-{p}.png)

<details><summary>End of the run (last frame of the recording)</summary>

![problem {num}: end of run](docs/img/run-{p}.png)

</details>
"""
s = re.sub(rf"\n\*\*{num}\. `{re.escape(p)}`\*\*:.*?</details>\n", "\n", s, flags=re.S)
k = s.index("\n---\n\n## 5. Run notes")
s = s[:k] + block + s[k:]

# Scorecard from the per-problem table
graded, passed, failed, invalid, scores, times = 0, 0, 0, 0, [], []
for r in re.finditer(r"^\| \d+ \| `[^`]+` \| ([^|]+) \| ([^|]*) \| ([^|]*) \|", s, re.M):
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
print(f"README: {p} → {status}, {score:.0f}/100; scorecard {run}/17, {passed} passed, avg {avg}")
