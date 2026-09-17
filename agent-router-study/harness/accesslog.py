#!/usr/bin/env python3
"""Envoy 접근 로그로 지연을 구간에 귀속시킨다.

한 요청이 두 줄을 남긴다. 클라이언트에서 들어와 MCP 프록시로 가는 줄(안쪽 다리)과
프록시가 백엔드로 나가는 줄(바깥 다리)이다. route_name으로 나눈다.

duration은 요청 전체 시간이고 x-envoy-upstream-service-time은 업스트림이 첫
바이트를 돌려줄 때까지다. 둘의 차이가 응답을 흘려보내는 데 쓴 시간이다.
"""
import argparse, collections, json, statistics, sys


def pct(xs, p):
    if not xs:
        return None
    xs = sorted(xs)
    return round(xs[min(len(xs) - 1, int(round(p / 100 * (len(xs) - 1))))], 2)


def leg(rec):
    rn = rec.get("route_name") or ""
    if "ai-eg-mcp-main" in rn:
        return "안쪽(클라이언트 -> MCP 프록시)"
    if "ai-eg-mcp-br" in rn:
        return "바깥(MCP 프록시 -> 백엔드)"
    if "raw-mcpb" in rn:
        return "대조군(MCP 프록시 없음)"
    return f"기타({rn[:40]})"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    a = ap.parse_args()
    legs = collections.defaultdict(lambda: {"dur": [], "ust": [], "codes": collections.Counter()})
    for f in a.files:
        for line in open(f, errors="replace"):
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                r = json.loads(line)
            except json.JSONDecodeError:
                continue
            if "duration" not in r:
                continue
            d = legs[leg(r)]
            if isinstance(r.get("duration"), (int, float)):
                d["dur"].append(r["duration"])
            try:
                d["ust"].append(float(r.get("x-envoy-upstream-service-time") or 0))
            except (TypeError, ValueError):
                pass
            d["codes"][r.get("response_code")] += 1

    print("| 구간 | 건수 | duration p50 | p95 | 첫바이트 p50 | 차이 p50 | 응답코드 |")
    print("|---|---|---|---|---|---|---|")
    for name in sorted(legs):
        d = legs[name]
        diff = [x - y for x, y in zip(sorted(d["dur"]), sorted(d["ust"]))]
        codes = ", ".join(f"{k}:{v}" for k, v in d["codes"].most_common(3))
        print(f"| {name} | {len(d['dur'])} | {pct(d['dur'],50)}ms | {pct(d['dur'],95)}ms | "
              f"{pct(d['ust'],50)}ms | {pct(diff,50)}ms | {codes} |")


if __name__ == "__main__":
    main()
