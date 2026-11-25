#!/usr/bin/env python3
# report_sweep.py: model sweep aggregation (001-004 x A/B/C x 4 models x N=3).
# Token parsing reuses AIOps collect.py parse_claude_raw, with token totals taken from modelUsage (2026-11-25).
import json
import statistics
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str((HERE.parents[2] / "AIOps-Agent-Benchmark" / "scripts")))
from collect import parse_claude_raw

RUNS = HERE / "runs"
MODELS = ["haiku-4-5", "sonnet-4-6", "sonnet-5", "opus-4-8", "fable-5"]
PREFIXES = ("haiku-r", "sonnet-r", "sonnet5-r", "opus-r", "fable-r")


def model_usage_totals(raw_path):
    """마지막 result 이벤트의 modelUsage 합계(입력, 캐시 쓰기, 캐시 읽기, 출력). 없으면 None.

    Claude Code 는 백그라운드 작업이 끝날 때마다 result 이벤트를 새로 내고 각 이벤트의 usage 는 그 구간만 담는다.
    parse_claude_raw 는 마지막 이벤트의 usage 만 남기므로 이런 실행에서 적게 집계된다. modelUsage 는 실행 전체의
    누적이라 이 값을 사용한다(2026-11-25 보정, 스윕 180회 가운데 2회가 해당).
    """
    last = None
    for line in Path(raw_path).read_text(encoding="utf-8", errors="ignore").splitlines():
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        if ev.get("type") == "result":
            last = ev
    mu = (last or {}).get("modelUsage") or {}
    if not mu:
        return None
    s = lambda k: sum(v.get(k, 0) for v in mu.values())
    return s("inputTokens"), s("cacheCreationInputTokens"), s("cacheReadInputTokens"), s("outputTokens")


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
        tot = model_usage_totals(rp)
        if tot:
            m.input_tokens, m.cache_creation_input_tokens, m.cache_read_input_tokens, m.output_tokens = tot
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
    return f"{(b - a) / a * 100:+.1f}%"


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
