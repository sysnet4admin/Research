#!/usr/bin/env python3
"""주말 보강 캠페인(W1~W5) 결과를 본측정과 함께 요약한다.

발행문에 어떻게 반영할지 판단할 수 있는 형태로 낸다. 특히 W1은 편차 자체가
결론이므로 중앙값만 내지 않고 전체 관측을 보여 준다.

사용: python3 harness/analyze_weekend.py [본측정디렉토리] [주말디렉토리] [게이트웨이kill디렉토리]
"""

import glob
import json
import os
import statistics
import sys


def load(pattern):
    out = []
    for f in sorted(glob.glob(pattern)):
        if f.endswith(".kill.json"):
            continue
        try:
            out.append((os.path.basename(f), json.load(open(f))))
        except Exception:
            pass
    return out


def rps(recs):
    return [round(d["achieved_rps"], 1) for _, d in recs]


def line(label, vals, extra=""):
    if not vals:
        print(f"  {label:34} (없음)")
        return
    print(f"  {label:34} 중앙 {statistics.median(vals):6.1f}  "
          f"범위 {min(vals):6.1f}~{max(vals):6.1f}  n={len(vals):2}  {extra}")


def w1(main, wk):
    print("\n== W1: 구 스펙 연결 재사용, 레플리카 4 ==")
    print("본측정 3회로는 편차가 커서 중앙값을 쓰기 어려웠다. 반복을 늘려 확인한다.")
    a = rps(load(f"{main}/m1-a-echo-reuse-r4-rep*.json"))
    b = rps(load(f"{wk}/w1-a-reuse-r4-rep*.json"))
    line("본측정 3회", a)
    line("보강 10회", b)
    allv = a + b
    line("합계", allv)
    if allv:
        sd = statistics.stdev(allv) if len(allv) > 1 else 0
        cv = sd / statistics.mean(allv) * 100
        print(f"  -> 표준편차 {sd:.1f}, 변동계수 {cv:.0f}%")
        print("  -> " + ("편차가 커서 단일 값으로 쓰면 안 된다. 범위로 적는다."
                         if cv > 15 else "값이 안정적이다. 중앙값을 써도 된다."))


def w2(wk):
    print("\n== W2: 세션이 몇 번째 새 연결에서 깨지는가 ==")
    print("레플리카 N개면 기하분포 기댓값은 N/(N-1)이다. 실측과 맞는지 본다.")
    for f in sorted(glob.glob(f"{wk}/w2-onset-r*.json")):
        d = json.load(open(f))
        n, exp = d["replicas"], d.get("expected_geometric")
        if d["mean"] is None:
            print(f"  레플리카 {n}: 관측 없음")
            continue
        print(f"  레플리카 {n}: 평균 {d['mean']:.2f} (이론 {exp:.2f}), "
              f"중앙값 {d['median']}, 첫 연결에서 바로 {d['first_try_share'] * 100:.0f}%, "
              f"시행 {d['trials']}회, 절단 {d['censored']}")
        print(f"    이론 첫 실패 확률 {(n - 1) / n * 100:.0f}%")


def w3(main, wk):
    print("\n== W3: 신 스펙 연결 재사용 (본측정은 새 연결만 쟀다) ==")
    for r in (1, 2, 4):
        close = rps(load(f"{main}/m1-b-echo-close-r{r}-rep*.json"))
        reuse = rps(load(f"{wk}/w3-b-reuse-r{r}-rep*.json"))
        line(f"레플리카 {r} 새 연결(본측정)", close)
        line(f"레플리카 {r} 연결 재사용(보강)", reuse)
    allr = [v for r in (1, 2, 4) for v in rps(load(f"{wk}/w3-b-reuse-r{r}-rep*.json"))]
    losses = sum(d["session_loss"] + d["handle_loss"]
                 for r in (1, 2, 4) for _, d in load(f"{wk}/w3-b-reuse-r{r}-rep*.json"))
    if allr:
        print(f"  -> 재사용 전 구간 유실 {losses}건. "
              + ("연결 방식과 무관하게 평탄하다." if losses == 0 else "유실이 나왔다. 확인 필요."))


def w4(wk):
    print("\n== W4: 신 스펙 포화점 (레플리카 4, 새 연결) ==")
    print("200rps가 상한의 어디쯤인지 수치로 말할 수 있게 한다.")
    rows = []
    for f in sorted(glob.glob(f"{wk}/w4-b-close-r4-rps*.json"),
                    key=lambda p: int(p.split("rps")[-1].split(".")[0])):
        d = json.load(open(f))
        target = int(f.split("rps")[-1].split(".")[0])
        got = d["achieved_rps"]
        rows.append((target, got, d["latency_ms"]["p99"],
                     d["session_loss"] + d["handle_loss"]))
        print(f"  목표 {target:4} -> 달성 {got:6.1f} ({got / target * 100:5.1f}%)  "
              f"p99 {d['latency_ms']['p99']:7.1f}  유실 {d['session_loss'] + d['handle_loss']}")
    hit = [t for t, g, _, _ in rows if g < t * 0.95]
    if hit:
        print(f"  -> {hit[0]}rps 부터 목표를 못 따라간다. 200rps는 그 아래다.")
    elif rows:
        print(f"  -> {rows[-1][0]}rps 까지 목표를 따라갔다. 상한은 그보다 위다.")


def w5(gw):
    if not gw or not os.path.isdir(gw):
        print("\n== W5: 게이트웨이 파드 교체 == (미실행)")
        return
    print("\n== W5: 게이트웨이 경유에서 파드 교체 ==")
    print("게이트웨이가 세션을 붙들고 있을 때 그 파드가 사라지면 어떻게 되는가.")
    for spec, label in (("a", "구 스펙 Stateful"), ("b", "신 스펙 Stateless")):
        recs = load(f"{gw}/w5-agw-{spec}-kill-rep*.json")
        if not recs:
            continue
        sloss = sum(d["session_loss"] for _, d in recs)
        hloss = sum(d["handle_loss"] for _, d in recs)
        line(f"{label}", rps(recs), f"세션유실 {sloss} 핸들유실 {hloss}")
    kills = glob.glob(f"{gw}/w5-agw-*-kill-rep*.kill.json")
    ok = sum(1 for f in kills if json.load(open(f)).get("killed"))
    print(f"  파드 종료 성사 {ok}/{len(kills)}")


if __name__ == "__main__":
    base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    main = sys.argv[1] if len(sys.argv) > 1 else f"{base}/runs/main-2026-08-06b"
    wk = sys.argv[2] if len(sys.argv) > 2 else f"{base}/runs/weekend-2026-08-08"
    gw = sys.argv[3] if len(sys.argv) > 3 else f"{base}/runs/agw-kill-2026-08-08"
    print(f"본측정 {main}\n보강   {wk}\n게이트웨이 {gw}")
    w1(main, wk)
    w2(wk)
    w3(main, wk)
    w4(wk)
    w5(gw)
