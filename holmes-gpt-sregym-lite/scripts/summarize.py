"""Collect SREGym results for the holmesgpt agent into results/.

Reads every results/<run>/holmesgpt/<problem>/*_results.csv under the SREGym
checkout (latest run per problem wins), copies the HolmesGPT answer for each
problem, and writes results/summary.md + results/results.csv.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import shutil
from datetime import datetime
from pathlib import Path

LITE = [
    "cronjob_sidecar_blocks_completion_hotel_reservation",
    "edge_request_filter_cpu_saturation",
    "network_policy_block",
    "env_variable_shadowing_astronomy_shop",
    "mutating_webhook_resource_limits_social_network",
    "finalizer_deadlock_controller_hotel_reservation",
    "kafka_poison_pill_hol_block",
    "internal_traffic_policy_local_astronomy_shop",
    "service_dns_resolution_failure_social_network",
    "service_wrong_pod_selection_hotel_reservation",
    "namespace_memory_limit",
    "valkey_auth_disruption",
    "secret_rotation_stale_env_credentials_astronomy_shop",
    "unschedulable_incorrect_port_assignment",
    "duplicate_pvc_mounts_social_network",
    "rolling_update_misconfigured_social_network",
    "search_rate_retry_collapse_hotel_reservation",
]


def latest_rows(sregym: Path, run: str | None) -> dict[str, tuple[Path, dict]]:
    rows: dict[str, tuple[Path, dict]] = {}
    for csv_path in sorted((sregym / "results").glob(f"{run or '*'}/holmesgpt/*/*_holmesgpt_results.csv")):
        with csv_path.open() as f:
            for row in csv.DictReader(f):
                rows[row["problem_id"]] = (csv_path.parent, row)
    return rows


# Earlier ai_sre experiments: hand-picked scenarios, outcomes taken from their READMEs.
PRIOR_EXPERIMENTS = [
    ("1", "[HolmesGPT v0.30](holmes-gpt/README.md)", "iximiuz Labs, 3 scenarios", "2/3 (+1 partial)", "—", "Defer"),
    ("2", "[K8sGPT 0.4.33](k8sgpt/README.md)", "iximiuz Labs, 2 scenarios", "0/2 (CLI)", "—", "Reject"),
    ("3", "[OpenSRE 0.1](opensre/README.md)", "observability-stack, 3 scenarios", "0/3", "—", "Defer"),
    ("4", "[HolmesGPT v0.45](holmes-gpt-sre-gym/README.md)", "observability-stack, 3 scenarios", "2/3 (+1 partial)", "—", "Pilot"),
]


def scorecard(rows: dict, run: str | None) -> dict:
    graded = [r for _, r in rows.values() if r.get("Diagnosis.success") in ("True", "False")]
    scores = [float(r["Diagnosis.accuracy"]) for r in graded if r.get("Diagnosis.accuracy")]
    times = [float(r["phase.stage:diagnosis.duration_s"]) for r in graded if r.get("phase.stage:diagnosis.duration_s")]
    return {
        "run": len(rows),
        "passed": sum(r["Diagnosis.success"] == "True" for r in graded),
        "failed": sum(r["Diagnosis.success"] == "False" for r in graded),
        "not_graded": len(rows) - len(graded),
        "avg_score": sum(scores) / len(scores) if scores else None,
        "avg_min": sum(times) / len(times) / 60 if times else None,
    }


def replace_block(path: Path, name: str, body: str) -> None:
    text = path.read_text()
    block = f"<!-- {name}:START -->\n{body}\n<!-- {name}:END -->"
    path.write_text(re.sub(rf"<!-- {name}:START -->.*?<!-- {name}:END -->", lambda _: block, text, flags=re.S))


def status(row: dict) -> str:
    if row.get("deploy_failed") == "True":
        return "deploy failed"
    if row.get("run_status") == "incomplete":
        return f"incomplete ({row.get('incomplete_reason', '')})"
    if row.get("timed_out") == "True":
        return "agent timed out"
    return {"True": "✅ pass", "False": "❌ fail"}.get(row.get("Diagnosis.success", ""), "—")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--sregym", type=Path, required=True)
    p.add_argument("--out", type=Path, default=Path("results"))
    p.add_argument("--run", help="SREGym results/<run> directory name (default: latest result per problem)")
    p.add_argument("--readme", type=Path, help="README whose RESULTS block is replaced with the summary")
    p.add_argument("--root-readme", type=Path, help="ai_sre README whose SCORECARD block covers all experiments")
    args = p.parse_args()

    raw = args.out / "raw"
    answers = args.out / "answers"
    raw.mkdir(parents=True, exist_ok=True)
    answers.mkdir(parents=True, exist_ok=True)

    rows = latest_rows(args.sregym, args.run)
    fields: list[str] = []
    table = [
        "| # | Problem | Diagnosis | Score | Investigation | Judge notes |",
        "|---|---------|-----------|------:|--------------:|-------------|",
    ]
    passed = evaluated = 0
    for i, pid in enumerate(LITE, 1):
        if pid not in rows:
            table.append(f"| {i} | `{pid}` | not run | | | |")
            continue
        run_dir, row = rows[pid]
        fields += [k for k in row if k not in fields]
        st = status(row)
        if st in ("✅ pass", "❌ fail"):
            evaluated += 1
            passed += st == "✅ pass"
        notes = (row.get("Diagnosis.reasoning") or row.get("Diagnosis.judgment") or "").replace("\n", " ").replace("|", "/")
        score = row.get("Diagnosis.accuracy") or ""
        secs = row.get("phase.stage:diagnosis.duration_s") or ""
        took = f"{float(secs) / 60:.1f} min" if secs else ""
        table.append(f"| {i} | `{pid}` | {st} | {score} | {took} | {notes[:220]} |")

        shutil.copytree(run_dir, raw / pid, dirs_exist_ok=True)
        for log in sorted(run_dir.rglob("holmes_*.json"))[-1:]:
            result = json.loads(log.read_text()).get("result", "")
            (answers / f"{pid}.md").write_text(f"# {pid}\n\n{result}\n")

    with (args.out / "results.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for pid in LITE:
            if pid in rows:
                w.writerow(rows[pid][1])

    header = (
        f"**Diagnosis pass rate: {passed}/{evaluated} evaluated** · {len(rows)}/{len(LITE)} problems run"
        f" · run `{args.run or 'latest per problem'}` · updated {datetime.now():%Y-%m-%d %H:%M}"
    )
    summary = header + "\n\n" + "\n".join(table)
    (args.out / "summary.md").write_text(summary + "\n")
    sc = scorecard(rows, args.run)
    pct = f"{100 * sc['passed'] / (sc['passed'] + sc['failed']):.0f}%" if sc["passed"] + sc["failed"] else "—"
    avg_score = f"{sc['avg_score']:.0f}/100" if sc["avg_score"] is not None else "—"
    avg_min = f"{sc['avg_min']:.1f} min" if sc["avg_min"] is not None else "—"
    card = "\n".join([
        "| Problems run | ✅ Passed | ❌ Failed | ⚠️ Not graded | Pass rate | Avg judge score | Avg investigation |",
        "|---:|---:|---:|---:|---:|---:|---:|",
        f"| {sc['run']}/{len(LITE)} | {sc['passed']} | {sc['failed']} | {sc['not_graded']} | {pct} | {avg_score} | {avg_min} |",
    ])
    if args.readme:
        replace_block(args.readme, "SCORECARD", f"### Scorecard\n\n{card}")
        replace_block(args.readme, "RESULTS", summary)
    if args.root_readme:
        lines = [
            "Updated automatically after every SREGym-Lite problem. Experiments 1–4 are hand-picked scenarios;",
            "experiment 5 is graded by SREGym's LLM judge against the known root cause.",
            "",
            "| # | Experiment | Test set | Correct RCA | Avg judge score | Verdict |",
            "|---|------------|----------|-------------|----------------:|---------|",
            *[f"| {' | '.join(r)} |" for r in PRIOR_EXPERIMENTS],
            f"| 5 | [HolmesGPT v0.45 on SREGym-Lite](holmes-gpt-sregym-lite/README.md) | SREGym-Lite, "
            f"{sc['run']}/{len(LITE)} problems run | {sc['passed']}/{sc['passed'] + sc['failed']} ({pct}) | {avg_score} | "
            f"{'In progress' if sc['run'] < len(LITE) else 'See README'} |",
            "",
            f"_Last updated {datetime.now():%Y-%m-%d %H:%M}._",
        ]
        replace_block(args.root_readme, "SCORECARD", "\n".join(lines))
    print(summary)


if __name__ == "__main__":
    main()
