#!/usr/bin/env python3
# report_sweep.py: model sweep aggregation (001-004 x A/B/C x 4 models x N=3).
# Token parsing reuses AIOps collect.py parse_claude_raw.
import json
import statistics
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str((HERE.parents[2] / "AIOps-Agent-Benchmark" / "scripts")))
from collect import parse_claude_raw

RUNS = HERE / "runs"
MODELS = ["haiku-4-5", "sonnet-4-6", "opus-4-8", "fable-5"]
PREFIXES = ("haiku-r", "sonnet-r", "opus-r", "fable-r")


def load():
    rows = []
    for d in sorted(RUNS.glob("agentsmd-*")):
        mp, rp, tp = d / "meta.json", d / "raw.json", d / "timing.json"
        if not (mp.exists() and rp.exists() and tp.exists()):
            continue
        meta = json.loads(mp.read_text())
        tag = meta.get("tag", "")
        if not any(tag.startswith(p) for p in PREFIXES):
            continue
        m = parse_claude_raw(rp, tp)
        rows.append({
            "cond": meta["cond"],
            "scenario": meta["scenario"],
            "model": meta["model"].replace("claude-", ""),
            "rc": meta.get("agent_rc"),
            "wall": m.wall_time_seconds,
            "eff": m.effective_input_tokens,
            "cc": m.cache_creation_input_tokens,
            "cr": m.cache_read_input_tokens,
            "inp": m.input_tokens,
            "out": m.output_tokens,
            "tc": m.tool_calls_total,
        })
    return rows


def med(rows, model, cond, field):
    v = [r[field] for r in rows if r["model"] == model and r["cond"] == cond and r["rc"] == 0]
    return statistics.median(v) if v else None


def pct(b, a):
    if not a:
        return "-"
    return str(round((b - a) / a * 100)) + "%"


def table(rows, field, unit):
    print("")
    print("=== " + field + " (" + unit + ") median: model x cond ===")
    print("model         A          B          C        BvsA    CvsA")
    for mo in MODELS:
        a = med(rows, mo, "A", field)
        b = med(rows, mo, "B", field)
        c = med(rows, mo, "C", field)
        if a is None:
            print(mo + "  (no data)")
            continue
        line = mo.ljust(12)
        line += "  " + str(round(a, 1)).rjust(9)
        line += "  " + str(round(b, 1)).rjust(9)
        line += "  " + str(round(c, 1)).rjust(9)
        line += "   " + pct(b, a).rjust(6)
        line += "  " + pct(c, a).rjust(6)
        print(line)


def main():
    rows = load()
    clean = sum(1 for r in rows if r["rc"] == 0)
    print("sweep rows: " + str(len(rows)) + " (clean rc=0: " + str(clean) + ")")
    table(rows, "cc", "tokens (cache write = 1-time context load, cost-relevant)")
    table(rows, "inp", "tokens (uncached input)")
    table(rows, "cr", "tokens (cache read, accumulates with turns)")
    table(rows, "eff", "tokens (input+cc+cr sum)")
    table(rows, "wall", "seconds")
    table(rows, "out", "tokens")
    table(rows, "tc", "count")


if __name__ == "__main__":
    main()
