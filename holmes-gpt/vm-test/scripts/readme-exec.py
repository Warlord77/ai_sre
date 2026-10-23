"""Rebuild the README's "Execution" section from the per-problem table.

Graded problems get their answer screenshot, the run's GIF and its last frame; invalid ones get the
screenshot of their log summary. Media that doesn't exist yet is left out.
Usage: python3 scripts/readme-exec.py
"""
import re
from pathlib import Path

here = Path(__file__).resolve().parent.parent
readme = here / "README.md"
s = readme.read_text()

INTRO = """### Execution

Each graded problem shows HolmesGPT's root cause with the judge's verdict, a GIF of the whole run (20×
speed: deploy, fault injection, HolmesGPT's investigation, judging, cleanup) and the run's last frame.
Logs are in `results/<problem>/`: `sregym.log` (conductor), `holmes.log` (HolmesGPT transcript),
`holmes.json` (every tool call, tokens, answer), `judge.csv` (verdict, checklist, timings), `run.log`
(`make run-one` output) and `answer.md`. The asciinema casts replay a run at full speed
(`asciinema play recordings/run-<problem>.cast`).
"""

def exists(rel):
    return (here / rel).exists()

blocks = []
for m in re.finditer(r"^\| (\d+) \| `([^`]+)` \|\s*([^|]+?)\s*\|\s*([^|]*?)\s*\|", s, re.M):
    num, p, status, score = m.groups()
    if not status[:1] in "✅❌⚠":
        continue  # pending / running, or an observation-table row
    if status.startswith("⚠"):
        logs = next((d for d in (f"results/{p}--invalid-model-stall", f"results/{p}") if exists(d)), None)
        b = f"**{num}. `{p}`**: {status}" + (f" · [logs]({logs}/)" if logs else "") + "\n"
        if exists(f"docs/img/invalid-{p}.png"):
            b += f"\n![problem {num}: why the run is invalid](docs/img/invalid-{p}.png)\n"
    else:
        b = f"**{num}. `{p}`**: {status} · score {score}/100 · [logs](results/{p}/)"
        if exists(f"recordings/run-{p}.cast"):
            b += f" · [asciinema cast](recordings/run-{p}.cast)"
        b += "\n"
        if exists(f"docs/img/answer-{p}.png"):
            b += f"\n![problem {num}: HolmesGPT answer and judge verdict](docs/img/answer-{p}.png)\n"
        if exists(f"recordings/run-{p}.gif"):
            b += f"\n*Run video (20× speed):*\n\n![problem {num}: run video](recordings/run-{p}.gif)\n"
        if exists(f"docs/img/run-{p}.png"):
            b += (f"\n<details><summary>End of the run (last frame)</summary>\n\n"
                  f"![problem {num}: end of run](docs/img/run-{p}.png)\n\n</details>\n")
    blocks.append(b)

start = s.index("### Execution")
end = s.index("\n---\n\n## 5. Run notes")
s = s[:start] + INTRO + "\n" + "\n".join(blocks) + s[end:]
readme.write_text(s)
print(f"Execution section: {len(blocks)} problem(s)")
