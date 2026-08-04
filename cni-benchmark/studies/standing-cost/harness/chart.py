#!/usr/bin/env python3
"""상시 비용 지도 SVG 생성: idle 메모리(x) 대 churn CPU(y, 로그) 산점도.

analysis/summary.json에서 스택 총합을 계산해 그린다 (AIOps 점도표 선례를 따라
재생성 가능한 스크립트로 유지). x축 메모리는 process working set + eBPF map.

사용: python3 harness/chart.py analysis/summary.json > assets/standing-cost-map.svg
"""

import json
import math
import sys

sys.path.insert(0, __path__[0] if False else "harness")
from aggregate import totals  # noqa: E402

FAMILY = {
    "C": ("Calico", "#c1442e"), "X": ("Cilium", "#6b5b95"),
    "F": ("Flannel", "#2e6f9e"), "A": ("Antrea", "#3a7d44"),
    "K": ("kube-router", "#a07419"),
}

# 점 라벨: 공개 코드 + 핵심 구성 (그림 단독으로 읽히도록)
# 데이터 코드(C/X/F/A/K)는 측정 당시 이름, 공개 문서는 Ca/Ci/Fl/An/Ku 사용
LABELS = {
  "ko": {
    "C1": "Ca1 operator", "C2": "Ca2 eBPF", "C3": "Ca3 manifest", "C4": "Ca4 +BGP",
    "X1": "Ci1 기본", "X2": "Ci2 Hubble off", "X3": "Ci3 +KPR", "X4": "Ci4 +netkit",
    "F1": "Fl1 기본", "F1n": "Fl1n nftables",
    "A1": "An1 기본", "A2": "An2 FlowExporter",
    "K1": "Ku1 전기능", "K2": "Ku2 CNI만",
  },
  "en": {
    "C1": "Ca1 operator", "C2": "Ca2 eBPF", "C3": "Ca3 manifest", "C4": "Ca4 +BGP",
    "X1": "Ci1 default", "X2": "Ci2 Hubble off", "X3": "Ci3 +KPR", "X4": "Ci4 +netkit",
    "F1": "Fl1 default", "F1n": "Fl1n nftables",
    "A1": "An1 default", "A2": "An2 FlowExporter",
    "K1": "Ku1 all-features", "K2": "Ku2 CNI only",
  },
}
TEXT = {
  "ko": {"x": "idle 메모리 (클러스터 합, working set + eBPF map, MiB)",
         "y": "churn CPU (클러스터 합, mC, 1000mC=1코어, 로그 축)",
         "note1": "왼쪽 아래일수록", "note2": "상시 비용이 낮다"},
  "en": {"x": "idle memory (cluster total, working set + eBPF maps, MiB)",
         "y": "churn CPU (cluster total, mC, 1000mC = 1 core, log scale)",
         "note1": "lower-left =", "note2": "cheaper to run"},
}

# 라벨 배치 미세조정 (겹침 방지: dx, dy, anchor)
NUDGE = {
    "X3": (-10, -4, "end"), "X4": (-10, 12, "end"),
    "A1": (10, -4, "start"), "A2": (10, 12, "start"),
    "F1": (10, -4, "start"), "F1n": (10, 8, "start"),
    "K1": (10, 4, "start"), "K2": (10, 12, "start"),
    "C1": (-10, -6, "end"), "C4": (10, 2, "start"),
    "C2": (10, -4, "start"), "C3": (10, -6, "start"),
    "X1": (10, -4, "start"), "X2": (10, 14, "start"),
}


def main(path, lang="en"):
    LABEL = LABELS[lang]
    T = TEXT[lang]
    data = json.load(open(path))
    pts = []
    for cond, d in data.items():
        idle = d["phases"].get("idle")
        churn = d["phases"].get("churn")
        if not idle or not churn:
            continue
        mem = totals(idle)["stack"][1] + idle.get("_bpf_mib", 0)
        cpu = totals(churn)["stack"][0]
        pts.append((cond, mem, cpu))

    W, H = 760, 470
    ML, MR, MT, MB = 70, 150, 40, 60
    PW, PH = W - ML - MR, H - MT - MB
    xmax = 2600
    ymin, ymax = 100, 4000

    def X(v):
        return ML + v / xmax * PW

    def Y(v):
        return MT + PH - (math.log10(v) - math.log10(ymin)) / \
            (math.log10(ymax) - math.log10(ymin)) * PH

    s = []
    s.append(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" '
             f'font-family="Helvetica, Arial, sans-serif">')
    s.append(f'<rect width="{W}" height="{H}" fill="white"/>')

    # 격자와 축
    for gx in range(0, xmax + 1, 500):
        s.append(f'<line x1="{X(gx)}" y1="{MT}" x2="{X(gx)}" y2="{MT+PH}" '
                 f'stroke="#e8e8e8"/>')
        s.append(f'<text x="{X(gx)}" y="{MT+PH+18}" font-size="11" '
                 f'fill="#666" text-anchor="middle">{gx}</text>')
    for gy in (100, 200, 500, 1000, 2000, 4000):
        s.append(f'<line x1="{ML}" y1="{Y(gy)}" x2="{ML+PW}" y2="{Y(gy)}" '
                 f'stroke="#e8e8e8"/>')
        s.append(f'<text x="{ML-8}" y="{Y(gy)+4}" font-size="11" '
                 f'fill="#666" text-anchor="end">{gy}</text>')
    s.append(f'<rect x="{ML}" y="{MT}" width="{PW}" height="{PH}" '
             f'fill="none" stroke="#999"/>')
    s.append(f'<text x="{ML+PW/2}" y="{H-16}" font-size="12" fill="#333" '
             f'text-anchor="middle">{T["x"]}</text>')
    s.append(f'<text x="20" y="{MT+PH/2}" font-size="12" fill="#333" '
             f'text-anchor="middle" transform="rotate(-90 20 {MT+PH/2})">'
             f'{T["y"]}</text>')

    # 점과 라벨
    for cond, mem, cpu in sorted(pts):
        name, color = FAMILY[cond[0]]
        dx, dy, anchor = NUDGE.get(cond, (10, -4, "start"))
        s.append(f'<circle cx="{X(mem):.1f}" cy="{Y(cpu):.1f}" r="6" '
                 f'fill="{color}" fill-opacity="0.85"/>')
        s.append(f'<text x="{X(mem)+dx:.1f}" y="{Y(cpu)+dy:.1f}" font-size="11" '
                 f'fill="#222" text-anchor="{anchor}">{LABEL.get(cond, cond)}</text>')

    # 범례
    ly = MT + 6
    s.append(f'<text x="{ML+PW+14}" y="{ly}" font-size="11" fill="#333" '
             f'font-weight="bold">CNI</text>')
    for i, key in enumerate(["C", "X", "F", "A", "K"]):
        name, color = FAMILY[key]
        y = ly + 18 + i * 18
        s.append(f'<circle cx="{ML+PW+20}" cy="{y-4}" r="5" fill="{color}" '
                 f'fill-opacity="0.85"/>')
        s.append(f'<text x="{ML+PW+31}" y="{y}" font-size="11" '
                 f'fill="#333">{name}</text>')
    # 읽는 법
    s.append(f'<text x="{ML+PW+14}" y="{ly+120}" font-size="10" fill="#777">'
             f'{T["note1"]}</text>')
    s.append(f'<text x="{ML+PW+14}" y="{ly+134}" font-size="10" fill="#777">'
             f'{T["note2"]}</text>')

    s.append('</svg>')
    print("\n".join(s))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "en")
