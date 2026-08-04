#!/usr/bin/env python3
"""캠페인 결과 집계: 셀(조건 x 반복)별 페이즈 통계 -> 반복 간 중앙값 -> 표.

사용:
  python3 aggregate.py <run_dir> [<run_dir> ...] [--json out.json] [--md out.md]

셀 하나 = <run_dir>/repN/<COND>/metrics.jsonl. 처리 방식:
- CPU: counter를 인접 샘플 차분으로 rate(mC) 환산, 구성 요소별 클러스터 합의
  페이즈 평균. 메모리(ws/rss): 구성 요소별 클러스터 합의 페이즈 평균(MiB).
- eBPF map: bpf_memlock 노드 합의 페이즈 평균(MiB).
- stabilize 페이즈는 제외. 반복 간 집계는 중앙값(백신 검사 등 호스트 잡음 흡수).

구성 요소 분류: cni(에이전트/컨트롤러/operator 전부), proxy(kube-proxy),
control(k8s 자체, 총합 제외). 스택 총합 = cni + proxy (kube-proxy 대체 여부를
총합에 반영해야 조건 간 공정 비교가 됨).
"""

import argparse
import json
import statistics
import sys
from collections import defaultdict
from pathlib import Path

# 긴 이름 먼저 (cilium-operator가 cilium보다 먼저 걸려야 함)
KNOWN_BASES = [
    "calico-kube-controllers", "kube-controller-manager", "csi-node-driver",
    "antrea-controller", "cilium-operator", "calico-apiserver", "tigera-operator",
    "kube-flannel-ds", "kube-apiserver", "kube-scheduler", "cilium-envoy",
    "calico-typha", "antrea-agent", "calico-node", "kube-router", "kube-proxy",
    "coredns", "cilium", "etcd",
]

CLASS = {
    "kube-proxy": "proxy",
    "etcd": "control", "kube-apiserver": "control", "coredns": "control",
    "kube-controller-manager": "control", "kube-scheduler": "control",
}  # 나머지 KNOWN_BASES는 전부 cni

PHASES = ["idle", "density", "policy", "service", "churn", "node"]


def pod_base_name(pod):
    """파드명 -> 구성 요소 기반명. 알려진 접두사 우선, 아니면 해시 접미사 절단."""
    for base in KNOWN_BASES:
        if pod == base or pod.startswith(base + "-"):
            return base
    parts = pod.split("-")
    while len(parts) > 1 and parts[-1].isalnum() and 4 <= len(parts[-1]) <= 10 \
            and not parts[-1].isalpha():
        parts = parts[:-1]
    return "-".join(parts)


def comp_class(base):
    return CLASS.get(base, "cni")


def process_cell(path):
    """metrics.jsonl -> {phase: {comp: {cpu_m, ws, rss}, "_bpf": MiB}}"""
    prev_cpu = {}
    acc = defaultdict(lambda: defaultdict(lambda: {"cpu": [], "ws": [], "rss": []}))
    bpf = defaultdict(list)
    with open(path) as f:
        for line in f:
            if not line.strip():
                continue
            row = json.loads(line)
            phase = row.get("phase", "")
            ws_sum = defaultdict(float)
            rss_sum = defaultdict(float)
            cpu_sum = defaultdict(float)
            cpu_seen = False
            bpf_total, bpf_nodes = 0, 0
            for node, entry in row.get("nodes", {}).items():
                if "bpf" in entry:
                    bpf_total += entry["bpf"]["bpf_memlock_bytes"]
                    bpf_nodes += 1
                for c in entry.get("containers", []):
                    base = pod_base_name(c["pod"])
                    ws_sum[base] += c.get("working_set", 0)
                    rss_sum[base] += c.get("rss", 0)
                    if "cpu_seconds" in c:
                        ckey = (node, c["pod"], c["container"])
                        if ckey in prev_cpu:
                            pt, pv = prev_cpu[ckey]
                            dt = row["ts"] - pt
                            if 0 < dt < 120:
                                rate = (c["cpu_seconds"] - pv) / dt * 1000
                                if rate >= 0:
                                    cpu_sum[base] += rate
                                    cpu_seen = True
                        prev_cpu[ckey] = (row["ts"], c["cpu_seconds"])
            if phase in ("", "stabilize"):
                continue  # CPU 차분의 prev는 위에서 이미 채움
            for base in ws_sum:
                a = acc[phase][base]
                a["ws"].append(ws_sum[base])
                a["rss"].append(rss_sum[base])
                if cpu_seen:
                    a["cpu"].append(cpu_sum[base])
            if bpf_nodes == 3:  # 전 노드 값이 있는 틱만 (부분 합 왜곡 방지)
                bpf[phase].append(bpf_total)
    out = {}
    for phase, comps in acc.items():
        out[phase] = {}
        for base, v in comps.items():
            out[phase][base] = {
                "cpu_m": round(sum(v["cpu"]) / len(v["cpu"]), 2) if v["cpu"] else None,
                "ws_mib": round(sum(v["ws"]) / len(v["ws"]) / 1048576, 1),
                "rss_mib": round(sum(v["rss"]) / len(v["rss"]) / 1048576, 1),
                "n": len(v["ws"]),
            }
        if bpf.get(phase):
            out[phase]["_bpf_mib"] = round(
                sum(bpf[phase]) / len(bpf[phase]) / 1048576, 1)
    return out


def discover_cells(run_dirs, drops=()):
    """[(cond, rep_label, path)] rep_label = run명/repN.
    drops: "run명:조건" 목록. 무효 판정 셀 제외용 (예: 본 캠페인 A2는
    FeatureGate 미적용으로 무효, a2fix 런으로 대체. 2026-08-04)."""
    cells = []
    for rd in run_dirs:
        rd = Path(rd)
        for rep in sorted(rd.glob("rep*")):
            for cond_dir in sorted(rep.glob("*/")):
                m = cond_dir / "metrics.jsonl"
                if not m.exists() or m.stat().st_size == 0:
                    continue
                if f"{rd.name}:{cond_dir.name}" in drops:
                    continue
                cells.append((cond_dir.name, f"{rd.name}/{rep.name}", m))
    return cells


def median_or_none(vals):
    vals = [v for v in vals if v is not None]
    return round(statistics.median(vals), 2) if vals else None


def aggregate(cells):
    """조건 -> phase -> comp -> 중앙값 {cpu_m, ws_mib, rss_mib, reps}"""
    per_cond = defaultdict(list)  # cond -> [(rep_label, cell_result)]
    for cond, rep_label, path in cells:
        per_cond[cond].append((rep_label, process_cell(path)))

    result = {}
    for cond, reps in sorted(per_cond.items()):
        result[cond] = {"reps": [r for r, _ in reps], "phases": {}}
        for phase in PHASES:
            comps = defaultdict(lambda: defaultdict(list))
            bpfs = []
            for _, cell in reps:
                if phase not in cell:
                    continue
                for base, v in cell[phase].items():
                    if base == "_bpf_mib":
                        bpfs.append(v)
                        continue
                    for k in ("cpu_m", "ws_mib", "rss_mib"):
                        comps[base][k].append(v[k])
            if not comps:
                continue
            pdata = {}
            for base, kv in comps.items():
                pdata[base] = {k: median_or_none(vs) for k, vs in kv.items()}
                pdata[base]["reps"] = max(len(vs) for vs in kv.values())
            if bpfs:
                pdata["_bpf_mib"] = median_or_none(bpfs)
            result[cond]["phases"][phase] = pdata
    return result


def totals(pdata):
    """페이즈 데이터 -> {cni: (cpu, ws), proxy: (cpu, ws), stack: (cpu, ws)}"""
    t = {"cni": [0.0, 0.0], "proxy": [0.0, 0.0], "control": [0.0, 0.0]}
    for base, v in pdata.items():
        if base == "_bpf_mib":
            continue
        cls = comp_class(base)
        t[cls][0] += v["cpu_m"] or 0
        t[cls][1] += v["ws_mib"] or 0
    stack = [round(t["cni"][0] + t["proxy"][0], 1),
             round(t["cni"][1] + t["proxy"][1], 1)]
    return {k: [round(a, 1), round(b, 1)] for k, (a, b) in t.items()} | {"stack": stack}


def render_md(result):
    lines = ["# 집계 결과 (반복 간 중앙값, 클러스터 합)", ""]
    lines += ["## 조건 x 페이즈: 네트워킹 스택 총합 (CNI + kube-proxy)",
              "", "값 = CPU mC / working set MiB. bpf = eBPF map memlock MiB.", ""]
    header = "| 조건 | 반복 | " + " | ".join(PHASES) + " | idle bpf |"
    lines += [header, "|" + "---|" * (len(PHASES) + 3)]
    for cond, data in result.items():
        row = [cond, str(len(data["reps"]))]
        for phase in PHASES:
            pdata = data["phases"].get(phase)
            if not pdata:
                row.append("-")
                continue
            t = totals(pdata)["stack"]
            row.append(f"{t[0]:.0f} / {t[1]:.0f}")
        idle = data["phases"].get("idle", {})
        row.append(str(idle.get("_bpf_mib", "-")))
        lines.append("| " + " | ".join(row) + " |")
    lines.append("")

    lines += ["## 조건별 구성 요소 상세 (idle)", ""]
    for cond, data in result.items():
        idle = data["phases"].get("idle")
        if not idle:
            continue
        lines += [f"### {cond} (반복 {len(data['reps'])}회)", "",
                  "| 구성 요소 | 분류 | CPU mC | ws MiB | rss MiB |",
                  "|---|---|---|---|---|"]
        for base in sorted(idle, key=lambda b: (comp_class(b) if b != "_bpf_mib" else "z", b)):
            if base == "_bpf_mib":
                continue
            v = idle[base]
            lines.append(f"| {base} | {comp_class(base)} | {v['cpu_m']} | "
                         f"{v['ws_mib']} | {v['rss_mib']} |")
        t = totals(idle)
        lines.append(f"| **스택 총합** | cni+proxy | **{t['stack'][0]}** | "
                     f"**{t['stack'][1]}** | |")
        if "_bpf_mib" in idle:
            lines.append(f"| eBPF map | kernel | | {idle['_bpf_mib']} | |")
        lines.append("")
    return "\n".join(lines)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("run_dirs", nargs="+")
    p.add_argument("--json")
    p.add_argument("--md")
    p.add_argument("--drop", action="append", default=[],
                   help="제외할 셀: '런디렉토리명:조건' (반복 지정 가능)")
    args = p.parse_args()

    cells = discover_cells(args.run_dirs, drops=set(args.drop))
    print(f"셀 {len(cells)}개 발견", file=sys.stderr)
    result = aggregate(cells)
    if args.json:
        Path(args.json).write_text(json.dumps(result, ensure_ascii=False, indent=1))
        print(f"JSON -> {args.json}", file=sys.stderr)
    md = render_md(result)
    if args.md:
        Path(args.md).write_text(md)
        print(f"MD -> {args.md}", file=sys.stderr)
    else:
        print(md)


if __name__ == "__main__":
    main()
