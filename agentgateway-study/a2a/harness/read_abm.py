#!/usr/bin/env python3
"""abm(비용 3팔 교대) 판독기.

회차(n) 안에서 세 팔이 인접 측정이므로, 회차 단위로 팔 간 p50 차이를 만들고
스펙별로 중앙값을 낸다. 달성 rps와 shed도 함께 표기(생성기 포화 확인).

사용: python3 read_abm.py <runs/abm-0827b> [runs/abm-0827b-ext ...]
(여러 디렉토리를 주면 합본 판독. 회차 번호는 파일명에서 자동 검출)
"""
import json
import statistics
import sys
from pathlib import Path

ARMS = ("direct", "gwplain", "gwa2a")
SPECS = (("close", 100), ("close", 200), ("reuse", 100), ("reuse", 200))


def main(bases):
    cells = {}
    for base in bases:
        for f in Path(base).glob("abm-*.json"):
            # abm-<arm>-<mode>-rps<rps>-n<n>.json
            parts = f.stem.split("-")
            arm, mode, rps, n = parts[1], parts[2], int(parts[3][3:]), int(parts[4][1:])
            cells[(arm, mode, rps, n)] = json.load(open(f))
    all_n = sorted({k[3] for k in cells})

    for mode, rps in SPECS:
        rows = []
        for n in all_n:
            row = {}
            for arm in ARMS:
                d = cells.get((arm, mode, rps, n))
                if d is None:
                    continue
                row[arm] = d
            if len(row) == 3:
                rows.append((n, row))
        if not rows:
            continue
        print(f"\n== {mode} {rps}rps ({len(rows)}회차) ==")
        print(f"{'n':>2} {'dir p50':>8} {'gwp p50':>8} {'gwa p50':>8} "
              f"{'gwp-dir':>8} {'gwa-gwp':>8} {'gwa-dir':>8}  achieved(dir/gwp/gwa)")
        d1, d2, d3 = [], [], []
        for n, row in rows:
            p = {a: row[a]["latency_ms"]["p50"] for a in ARMS}
            ach = {a: row[a]["achieved_rps"] for a in ARMS}
            x1 = p["gwplain"] - p["direct"]
            x2 = p["gwa2a"] - p["gwplain"]
            x3 = p["gwa2a"] - p["direct"]
            d1.append(x1); d2.append(x2); d3.append(x3)
            print(f"{n:>2} {p['direct']:>8.1f} {p['gwplain']:>8.1f} {p['gwa2a']:>8.1f} "
                  f"{x1:>+8.1f} {x2:>+8.1f} {x3:>+8.1f}  "
                  f"{ach['direct']:.0f}/{ach['gwplain']:.0f}/{ach['gwa2a']:.0f}")
        print(f"중앙값                                       "
              f"{statistics.median(d1):>+8.2f} {statistics.median(d2):>+8.2f} "
              f"{statistics.median(d3):>+8.2f}")
        # p99와 오류/포화 요약
        for a in ARMS:
            p99s = [row[a]["latency_ms"]["p99"] for _, row in rows]
            errs = sum(row[a].get("gateway_error", 0) + row[a].get("other_fail", 0)
                       for _, row in rows)
            sheds = sum(row[a].get("shed") or 0 for _, row in rows)
            recon = [row[a].get("reconnects") for _, row in rows]
            print(f"  {a:8s} p99 중앙값 {statistics.median(p99s):6.1f}  "
                  f"err {errs}  shed {sheds}  reconnects {recon}")


if __name__ == "__main__":
    main(sys.argv[1:])
