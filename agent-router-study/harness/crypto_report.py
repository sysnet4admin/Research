#!/usr/bin/env python3
"""반복 횟수 두 회차를 나란히 놓는다."""
import json, os, re, sys

DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "runs")
CONDS = sys.argv[1:] or ["100000", "1000"]

def load(c, name):
    p = os.path.join(DIR, f"crypto-{c}", f"{name}.json")
    return json.load(open(p)) if os.path.exists(p) else None

def cpu(c):
    """부하 창 안의 표본만 센다. 첫 표본은 집계 창이 부하 이전을 봐서 뺀다."""
    p = os.path.join(DIR, f"crypto-{c}", "top.txt")
    if not os.path.exists(p):
        return []
    vals = []
    for line in open(p):
        m = re.search(r"ai-gateway-extproc\s+(\d+)m", line)
        if m:
            vals.append(int(m.group(1)))
    return vals

print("## 저부하 지연 (동시 1, 30초)\n")
print("| 반복 횟수 | 달성 rps | p50 | p95 |")
print("|---|---|---|---|")
for c in CONDS:
    d = load(c, "c1")
    if d:
        print(f"| {int(c):,} | {d['rps']} | {d['p50']}ms | {d['p95']}ms |")

print("\n## 포화 처리량 (동시 16, 180초)\n")
print("| 반복 횟수 | 달성 rps | p50 | p95 | 오류 |")
print("|---|---|---|---|---|")
for c in CONDS:
    d = load(c, "sat")
    if d:
        print(f"| {int(c):,} | {d['rps']} | {d['p50']}ms | {d['p95']}ms | {d['err']} |")

print("\n## 목표 고정 회차 (60초, 동시 16)\n")
print("| 반복 횟수 | 목표 | 모드 | 달성 | p50 | 보내지 못한 요청 |")
print("|---|---|---|---|---|---|")
for c in CONDS:
    for r in (50, 100):
        for m in ("close", "reuse"):
            d = load(c, f"r{r}-{m}")
            if d:
                print(f"| {int(c):,} | {r} | {m} | {d['rate_achieved']} | {d['p50']}ms | {d['shed']} |")

print("\n## 부하 중 extproc 컨테이너 CPU (밀리코어)\n")
print("| 반복 횟수 | 표본 | 첫 표본 | 창이 찬 뒤 최대 |")
print("|---|---|---|---|")
for c in CONDS:
    v = cpu(c)
    if v:
        print(f"| {int(c):,} | {len(v)}개 | {v[0]}m | {max(v)}m |")
