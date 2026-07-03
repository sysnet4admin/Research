#!/usr/bin/env python3
"""aggregate.py: runs/ 아래 회차들을 집계해 CSV와 조건별 요약을 출력한다.

토큰/툴콜 파싱은 AIOps collect.py의 parse_claude_raw를 import해 그대로 쓴다(복제 없음).
사용: python3 aggregate.py [--csv out.csv]
"""

import argparse
import csv
import json
import statistics
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
AIOPS_SCRIPTS = HERE.parents[2] / "AIOps-Agent-Benchmark" / "scripts"
sys.path.insert(0, str(AIOPS_SCRIPTS))

from collect import parse_claude_raw  # noqa: E402

RUNS = HERE / "runs"

FIELDS = [
    "iter", "cond", "scenario", "tag", "model", "agent_rc",
    "wall_time_s", "input_tokens", "cache_creation", "cache_read",
    "effective_input", "output_tokens", "tool_calls",
]


def collect_rows():
    rows = []
    for d in sorted(RUNS.glob("agentsmd-*")):
        meta_p = d / "meta.json"
        raw_p = d / "raw.json"
        timing_p = d / "timing.json"
        if not (meta_p.exists() and raw_p.exists() and timing_p.exists()):
            continue
        meta = json.loads(meta_p.read_text())
        m = parse_claude_raw(raw_p, timing_p)
        rows.append({
            "iter": d.name,
            "cond": meta.get("cond"),
            "scenario": meta.get("scenario"),
            "tag": meta.get("tag"),
            "model": meta.get("model"),
            "agent_rc": meta.get("agent_rc"),
            "wall_time_s": round(m.wall_time_seconds, 1),
            "input_tokens": m.input_tokens,
            "cache_creation": m.cache_creation_input_tokens,
            "cache_read": m.cache_read_input_tokens,
            "effective_input": m.effective_input_tokens,
            "output_tokens": m.output_tokens,
            "tool_calls": m.tool_calls_total,
        })
    return rows


def summarize(rows):
    print()
    print("=== 조건별 요약 (median [min-max], n) ===")
    for metric in ("wall_time_s", "effective_input", "output_tokens", "tool_calls"):
        print(f"\n{metric}:")
        for cond in ("A", "B", "C"):
            vals = [r[metric] for r in rows if r["cond"] == cond and r["agent_rc"] == 0]
            if not vals:
                print(f"  {cond}: (no clean runs)")
                continue
            med = statistics.median(vals)
            print(f"  {cond}: {med} [{min(vals)}-{max(vals)}], n={len(vals)}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", help="CSV 출력 경로")
    args = ap.parse_args()

    rows = collect_rows()
    if not rows:
        print("no runs found under", RUNS)
        return

    w = csv.DictWriter(sys.stdout, fieldnames=FIELDS)
    w.writeheader()
    w.writerows(rows)

    if args.csv:
        with open(args.csv, "w", newline="") as f:
            cw = csv.DictWriter(f, fieldnames=FIELDS)
            cw.writeheader()
            cw.writerows(rows)
        print(f"\nwrote {args.csv} ({len(rows)} rows)", file=sys.stderr)

    summarize(rows)


if __name__ == "__main__":
    main()
