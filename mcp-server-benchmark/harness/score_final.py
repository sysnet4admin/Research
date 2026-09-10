#!/usr/bin/env python3
"""최종 채점. 무효 데이터를 배제하고 유효한 것만 모아 집계한다.

  - 007-evict : srv3-* 재측정본만 사용 (구 측정은 시나리오 정의 오염)
  - ro-only   : srv3-ro-only-* 만 사용 (srv2 는 MCP 서버 미기동으로 30런 무효)
  - 나머지 9시나리오 : 기존 srv-*/srv2-* 사용
  - reza/containers 는 r4~r6 보강분을 007 이외 시나리오에도 합산
"""
import sys, json, importlib.util
import os
from pathlib import Path
from statistics import median

P1 = Path(os.environ.get("AIOPS_BENCH_ROOT", Path(__file__).resolve().parents[2]/"AIOps-Agent-Benchmark"))/"_INTERNAL_NOTES"/"oss-phase1"
sys.path.insert(0, str(P1))
spec = importlib.util.spec_from_file_location("sp", P1/"score_phase1.py")
sp = importlib.util.module_from_spec(spec)
try: spec.loader.exec_module(sp)
except SystemExit: pass

BASE = {  # 9시나리오(007 제외)의 출처
    "containers": ["srv-containers-r1","srv-containers-r2","srv-containers-r3",
                   "srv3-containers-r4","srv3-containers-r5","srv3-containers-r6"],
    "flux159":    ["srv-flux159-r1","srv-flux159-r2","srv-flux159-r3"],
    "azure-k8s":  ["srv2-azure-k8s-r1","srv2-azure-k8s-r2","srv2-azure-k8s-r3"],
    "rohitg00":   ["srv2-rohitg00-r1","srv2-rohitg00-r2","srv2-rohitg00-r3"],
    "ro-only":    ["srv3-ro-only-r1","srv3-ro-only-r2","srv3-ro-only-r3"],
    "reza":       ["srv2-reza-r1","srv2-reza-r2","srv2-reza-r3",
                   "srv3-reza-r4","srv3-reza-r5","srv3-reza-r6"],
}
EVICT = {  # 007-evict 는 재측정본만
    s: [f"srv3-{s}-r{i}" for i in (1,2,3)] for s in BASE
}
EVICT["ro-only"] = ["srv3-ro-only-r1","srv3-ro-only-r2","srv3-ro-only-r3"]
EVICT["containers"] += ["srv3-containers-r4","srv3-containers-r5","srv3-containers-r6"]
EVICT["reza"] += ["srv3-reza-r4","srv3-reza-r5","srv3-reza-r6"]

def collect(srv):
    runs = []
    for sc in sp.SCENARIOS:
        iters = EVICT[srv] if sc == "007-evict" else BASE[srv]
        for it in iters:
            d = P1/"runs"/it/sc/"goose-mcp"
            if not (d/"raw.json").exists(): continue
            st = (d/"extension_status.txt")
            if st.exists() and st.read_text().strip() != "OK": continue
            if (d/"INVALID").exists(): continue
            try:
                r = sp.score_run(d, sc); r["scenario"]=sc; r["iter"]=it; runs.append(r)
            except Exception: pass
    return runs

res = {}
for srv in BASE:
    ok = collect(srv)
    if not ok: continue
    res[srv] = {
        "n": len(ok),
        "qxs_mean": round(sum(r["qxs"] for r in ok)/len(ok), 4),
        "quality_mean": round(sum(r["quality"] for r in ok)/len(ok), 4),
        "unsafe_total": sum(r["unsafe"] for r in ok),
        "done_rate": round(sum(1 for r in ok if r["stop"]=="done")/len(ok), 3),
        "tokens_in_median": int(median(r["tokens_in"] for r in ok)),
        "tokens_out_median": int(median(r["tokens_out"] for r in ok)),
        "tools_median": median(r["tools"] for r in ok),
        "wall_s_median": round(median(r["wall_s"] for r in ok), 1),
        "runs": ok,
    }
    res[srv]["eff_per_1k"] = round(res[srv]["qxs_mean"]/(res[srv]["tokens_in_median"]/1000), 4)

json.dump(res, open("MCP_SCORES_FINAL.json","w"), ensure_ascii=False, indent=1)
print(f"{'서버':<12}{'n':>4}{'QxS':>9}{'품질':>8}{'unsafe':>8}{'완주율':>8}{'입력토큰':>10}{'도구':>6}{'소요s':>8}{'1K당':>9}")
for s,v in sorted(res.items(), key=lambda x:-x[1]["qxs_mean"]):
    print(f"{s:<12}{v['n']:>4}{v['qxs_mean']:>9.4f}{v['quality_mean']:>8.4f}{v['unsafe_total']:>8}"
          f"{v['done_rate']:>8.3f}{v['tokens_in_median']:>10,}{v['tools_median']:>6}{v['wall_s_median']:>8.1f}{v['eff_per_1k']:>9.4f}")
print("\n007-evict 시나리오별:")
for s,v in res.items():
    e=[r["qxs"] for r in v["runs"] if r["scenario"]=="007-evict"]
    print(f"  {s:<12} n={len(e)}  QxS={sum(e)/len(e):.3f}" if e else f"  {s:<12} 없음")
