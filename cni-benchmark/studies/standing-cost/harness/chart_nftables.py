#!/usr/bin/env python3
"""kube-proxy iptables 대 nftables 메모리 사용량 막대 그림.

analysis/summary.json의 F1(iptables)과 F1n(nftables)에서 kube-proxy의
구간별 working set(클러스터 합, MiB)을 뽑아 나란히 그린다.

사용: python3 harness/chart_nftables.py analysis/summary.json > assets/kube-proxy-nftables.svg
"""

import json
import sys

PHASES = ["idle", "service", "churn", "node"]
PHASE_LABEL = {
  "ko": {"idle": "idle", "service": "service\n(Service 200개)",
         "churn": "churn\n(파드 교체 중)", "node": "node\n(drain/재합류)"},
  "en": {"idle": "idle", "service": "service\n(200 Services)",
         "churn": "churn\n(pods being replaced)", "node": "node\n(drain/rejoin)"},
}
TITLE = {"ko": "kube-proxy 메모리 사용량: iptables 대 nftables (클러스터 합)",
         "en": "kube-proxy memory usage: iptables vs nftables (cluster total)"}
LEGEND = {"ko": ("iptables 모드 (Fl1, 기본값)", "nftables 모드 (Fl1n)"),
          "en": ("iptables mode (Fl1, the default)", "nftables mode (Fl1n)")}
COLOR_IPT = "#8a8f98"   # iptables: 중립 회색
COLOR_NFT = "#2e6f9e"   # nftables: Flannel 계열과 같은 파랑


def main(path, lang="en"):
    PHASE_KO = PHASE_LABEL[lang]
    data = json.load(open(path))
    ipt = {p: data["F1"]["phases"][p]["kube-proxy"]["ws_mib"] for p in PHASES}
    nft = {p: data["F1n"]["phases"][p]["kube-proxy"]["ws_mib"] for p in PHASES}

    W, H = 680, 376
    ML, MR, MT, MB = 60, 20, 46, 80
    PW, PH = W - ML - MR, H - MT - MB
    ymax = 400.0
    group_w = PW / len(PHASES)
    bar_w = 44
    gap = 10

    def Y(v):
        return MT + PH - v / ymax * PH

    s = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" '
         f'font-family="Helvetica, Arial, sans-serif">',
         f'<rect width="{W}" height="{H}" fill="white"/>']

    # 격자와 y축
    for gy in range(0, 401, 100):
        s.append(f'<line x1="{ML}" y1="{Y(gy)}" x2="{ML+PW}" y2="{Y(gy)}" '
                 f'stroke="#e8e8e8"/>')
        s.append(f'<text x="{ML-8}" y="{Y(gy)+4}" font-size="11" fill="#666" '
                 f'text-anchor="end">{gy}</text>')
    s.append(f'<text x="{ML-40}" y="{MT-14}" font-size="11" fill="#333">MiB</text>')
    s.append(f'<text x="{ML+PW/2}" y="{MT-14}" font-size="13" fill="#111" '
             f'text-anchor="middle" font-weight="bold">'
             f'{TITLE[lang]}</text>')

    for i, ph in enumerate(PHASES):
        cx = ML + group_w * i + group_w / 2
        x1 = cx - bar_w - gap / 2
        x2 = cx + gap / 2
        v1, v2 = ipt[ph], nft[ph]
        s.append(f'<rect x="{x1:.1f}" y="{Y(v1):.1f}" width="{bar_w}" '
                 f'height="{PH - (Y(v1)-MT):.1f}" fill="{COLOR_IPT}"/>')
        s.append(f'<rect x="{x2:.1f}" y="{Y(v2):.1f}" width="{bar_w}" '
                 f'height="{PH - (Y(v2)-MT):.1f}" fill="{COLOR_NFT}"/>')
        s.append(f'<text x="{x1+bar_w/2:.1f}" y="{Y(v1)-6:.1f}" font-size="11" '
                 f'fill="#333" text-anchor="middle">{v1:.0f}</text>')
        s.append(f'<text x="{x2+bar_w/2:.1f}" y="{Y(v2)-6:.1f}" font-size="11" '
                 f'fill="#333" text-anchor="middle">{v2:.0f}</text>')
        for j, line in enumerate(PHASE_KO[ph].split("\n")):
            s.append(f'<text x="{cx:.1f}" y="{MT+PH+16+j*13}" font-size="11" '
                     f'fill="#333" text-anchor="middle">{line}</text>')
        pct = (1 - v2 / v1) * 100
        # 구간 라벨(최대 2줄) 아래에 절감률 (겹침 방지: 라벨 영역 밖 고정 y)
        s.append(f'<text x="{cx:.1f}" y="{MT+PH+58}" font-size="11" fill="#2e6f9e" '
                 f'text-anchor="middle" font-weight="bold">-{pct:.0f}%</text>')

    # 범례
    lx = ML + 8
    s.append(f'<rect x="{lx}" y="{MT+6}" width="12" height="12" fill="{COLOR_IPT}"/>')
    s.append(f'<text x="{lx+18}" y="{MT+16}" font-size="11" fill="#333">'
             f'{LEGEND[lang][0]}</text>')
    s.append(f'<rect x="{lx}" y="{MT+26}" width="12" height="12" fill="{COLOR_NFT}"/>')
    s.append(f'<text x="{lx+18}" y="{MT+36}" font-size="11" fill="#333">'
             f'{LEGEND[lang][1]}</text>')

    s.append('</svg>')
    print("\n".join(s))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "en")
