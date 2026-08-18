#!/usr/bin/env python3
"""본측정 결과 집계: runs 디렉토리의 JSON을 읽어 마크다운 표로 요약."""

import json
import statistics
import sys
from collections import defaultdict
from pathlib import Path


def main():
    out_dir = Path(sys.argv[1])
    rows = []
    for f in sorted(out_dir.glob("*.json")):
        if f.name.endswith(".kill.json") or f.name == "versions.txt":
            continue
        d = json.loads(f.read_text())
        if "config" not in d:
            continue
        rows.append((f.stem, d))

    # rep 접미사를 제거해 그룹핑, 반복 중앙값 요약
    groups = defaultdict(list)
    for name, d in rows:
        base = name.rsplit("-rep", 1)[0] if "-rep" in name else name
        groups[base].append(d)

    lines = [
        "| 셀 | n | rps(중앙값) | p50 ms | 세션 유실 | handle 유실 | 재연결 | 오류 합 |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for base in sorted(groups):
        ds = groups[base]
        med = lambda key: statistics.median(x for x in (dd[key] for dd in ds) if x is not None)
        rps = statistics.median(d["achieved_rps"] for d in ds)
        p50s = [d["latency_ms"]["p50"] for d in ds if d["latency_ms"]["p50"] is not None]
        p50 = statistics.median(p50s) if p50s else None
        sloss = sum(d["session_loss"] for d in ds)
        hloss = sum(d["handle_loss"] for d in ds)
        rc = sum(d.get("reconnects", 0) for d in ds)
        errs = sum(sum(d["errors"].values()) for d in ds)
        lines.append(
            f"| {base} | {len(ds)} | {rps} | {p50} | {sloss} | {hloss} | {rc} | {errs} |"
        )

    md = "\n".join(lines)
    (out_dir / "SUMMARY.md").write_text(md + "\n")
    print(md)


if __name__ == "__main__":
    main()
