#!/usr/bin/env python3
"""rv 재측정 합본 판독: P4(규칙 수), A/B(경로 쌍), grm(guardrail 교대) 표.

사용: python3 harness/rv_read.py runs/rv-axes-0902 runs/rv-ab-0902 runs/rv-grm-0902
셀 JSON은 loadgen 출력 형식(latency_ms.p50/p99, achieved_rps, ok, shed, gateway_error).
"""
import glob, json, os, statistics as st, sys


def load(path):
    d = json.load(open(path))
    return dict(p50=d["latency_ms"]["p50"], p99=d["latency_ms"]["p99"],
                rps=d["achieved_rps"], ok=d["ok"], shed=d.get("shed", 0),
                err=d.get("gateway_error", 0) + d.get("other_fail", 0))


def cells(base, pattern):
    out = {}
    for p in sorted(glob.glob(os.path.join(base, pattern))):
        n = int(os.path.basename(p).rsplit("-n", 1)[1].split(".")[0])
        out[n] = load(p)
    return out


def med(xs):
    return st.median(xs) if xs else float("nan")


def p4(base):
    print(f"== P4 규칙 수 x rps ({base}) ==")
    print(f"{'규칙':>4} {'rps':>4} {'달성(최저)':>10} {'p50 중앙값':>10} {'p99 중앙값':>10} {'p99 범위':>12} {'오류':>4}")
    for r in (0, 1, 21):
        for rps in (100, 200):
            c = cells(base, f"p4-r{r}-rps{rps}-n*.json")
            if not c:
                continue
            v = list(c.values())
            print(f"{r:>4} {rps:>4} {min(x['rps'] for x in v):>10.1f} {med([x['p50'] for x in v]):>10.1f} "
                  f"{med([x['p99'] for x in v]):>10.1f} {min(x['p99'] for x in v):>5.1f}~{max(x['p99'] for x in v):<6.1f} "
                  f"{sum(x['err'] for x in v):>4}")
    print()


def ab(base):
    pre = "abr" if "abr" in os.path.basename(base.rstrip("/")) else "ab"
    print(f"== A/B 경로 쌍 {'reuse' if pre == 'abr' else 'close'} ({base}) ==")
    print(f"{'arm':>6} {'rps':>4} {'달성 중앙값':>10} {'p50 중앙값':>10} {'p99 중앙값':>10} {'p99 범위':>12} {'오류':>4} {'shed':>4}")
    for rps in (100, 200):
        d = cells(base, f"{pre}-direct-rps{rps}-n*.json")
        g = cells(base, f"{pre}-gw-rps{rps}-n*.json")
        for name, c in (("direct", d), ("gw", g)):
            v = list(c.values())
            if not v:
                continue
            print(f"{name:>6} {rps:>4} {med([x['rps'] for x in v]):>10.1f} {med([x['p50'] for x in v]):>10.1f} "
                  f"{med([x['p99'] for x in v]):>10.1f} {min(x['p99'] for x in v):>5.1f}~{max(x['p99'] for x in v):<6.1f} "
                  f"{sum(x['err'] for x in v):>4} {sum(x['shed'] for x in v):>4}")
        if d and g:
            diffs = [g[n]["p50"] - d[n]["p50"] for n in sorted(d) if n in g]
            print(f"       {rps:>4} 쌍 p50 증분: 중앙값 {med(diffs):+.2f} 평균 {st.mean(diffs):+.2f} (개별 {' '.join(f'{x:+.1f}' for x in diffs)})")
    print()


def grm(base):
    print(f"== guardrail off/on 교대 ({base}) ==")
    print(f"{'연결':>6} {'rps':>4} {'달성(off/on 범위)':>18} {'off p50':>8} {'on p50':>7} {'짝 증분 평균':>12} {'sd':>5} {'off p99':>8} {'on p99':>7} {'오류':>4}")
    for mode in ("close", "reuse"):
        for rps in (100, 200, 400):
            off = cells(base, f"grm-off-{mode}-rps{rps}-n*.json")
            on = cells(base, f"grm-on-{mode}-rps{rps}-n*.json")
            if not off or not on:
                continue
            diffs = [on[n]["p50"] - off[n]["p50"] for n in sorted(off) if n in on]
            ach = [x["rps"] for x in list(off.values()) + list(on.values())]
            print(f"{mode:>6} {rps:>4} {min(ach):>8.1f}~{max(ach):<9.1f} {med([x['p50'] for x in off.values()]):>8.1f} "
                  f"{med([x['p50'] for x in on.values()]):>7.1f} {st.mean(diffs):>+12.2f} {st.pstdev(diffs):>5.2f} "
                  f"{med([x['p99'] for x in off.values()]):>8.1f} {med([x['p99'] for x in on.values()]):>7.1f} "
                  f"{sum(x['err'] for x in list(off.values()) + list(on.values())):>4}")
            print(f"            개별 짝 증분: {' '.join(f'{x:+.1f}' for x in diffs)}   shed off/on: "
                  f"{sum(x['shed'] for x in off.values())}/{sum(x['shed'] for x in on.values())}")
    print()


if __name__ == "__main__":
    for base in sys.argv[1:]:
        if "axes" in base:
            p4(base)
        elif "-ab-" in base or "-abr-" in base or base.rstrip("/").endswith("ab"):
            ab(base)
        elif "grm" in base:
            grm(base)
