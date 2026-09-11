#!/usr/bin/env python3
"""발행용 SVG 차트 생성기 (a2a-study).

runs/rv-abm-0902 원값에서 그림 2종 x 언어 2종을 figures/에 만든다.
원자료 JSON은 저장소에 포함하지 않으므로, 클론 재현 시에는 자기 캠페인
디렉토리를 인자로 넘긴다.

  python3 harness/chart.py runs/rv-abm-0902

그림 1 cost-3arm: 조건별 세 경로 p50 절대값 점 + 연결선 + 증분 라벨.
그림 2 card-rewrite: 카드 재작성 매트릭스와 병기 카드 누설(결정론 프로브
결과의 도식화. 데이터 인자 불필요).
"""
import json
import statistics
import sys
from pathlib import Path

ARMS = ("direct", "gwplain", "gwa2a")
SPECS = (("close", 100), ("close", 200), ("reuse", 100), ("reuse", 200))

T = {
    "en": {
        "cost_title": "What each layer adds: p50 latency by path (ms)",
        "cost_sub": "A2A message/send, medians over 20 alternated rounds. agentgateway v1.5.0, virtualized lab: read relative, not absolute.",
        "arm": {"direct": "direct", "gwplain": "gateway (plain HTTP)", "gwa2a": "gateway (A2A on)"},
        "spec": lambda m, r: f"{m} {r} rps",
        "card_title": "Agent card rewriting: opt-in, and the mixed-format leak",
        "card_sub": "What the card advertises when fetched through the gateway (v1.5.0, deterministic probes)",
        "rows": ["v0.3 card (top-level url)", "v1.0 card (supportedInterfaces)", "both fields (transitional)"],
        "cols": ["appProtocol set", "no appProtocol"],
        "rewritten": "gateway address",
        "kept": "DIRECT address",
        "leak": "v0.3 field leaks:\nv0.3 readers bypass the gateway",
        "bypass": "direct calls skip policy and logging (5/5)",
    },
    "ko": {
        "cost_title": "층마다 무엇이 더해지는가: 경로별 p50 지연 (ms)",
        "cost_sub": "A2A message/send, 교대 20회차 중앙값. agentgateway v1.5.0, 가상 환경: 절대값이 아니라 상대 비교로 읽을 것.",
        "arm": {"direct": "직접", "gwplain": "게이트웨이 (일반 HTTP)", "gwa2a": "게이트웨이 (A2A 켬)"},
        "spec": lambda m, r: f"{m} {r}rps",
        "card_title": "에이전트 카드 재작성: 옵트인, 그리고 병기 형식 누설",
        "card_sub": "게이트웨이 경유로 조회한 카드가 광고하는 주소 (v1.5.0, 결정론 프로브)",
        "rows": ["v0.3 카드 (최상위 url)", "v1.0 카드 (supportedInterfaces)", "병기 카드 (전환기)"],
        "cols": ["appProtocol 있음", "appProtocol 없음"],
        "rewritten": "게이트웨이 주소",
        "kept": "직접 주소",
        "leak": "v0.3 필드 누설:\nv0.3 독자는 게이트웨이 우회",
        "bypass": "직접 호출은 정책과 로그를 건너뜀 (5/5)",
    },
}

C = {"direct": "#4a7c59", "gwplain": "#4472a8", "gwa2a": "#b0563a",
     "grid": "#d8d8d8", "text": "#222", "sub": "#666",
     "ok": "#e8f0e8", "bad": "#f7e3dc", "badline": "#b0563a"}
FONT = "font-family='Helvetica,Arial,sans-serif'"


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;")


def load(bases):
    raw = {}
    for base in bases:
        for f in Path(base).glob("abm-*.json"):
            p = f.stem.split("-")
            arm, mode, rps, n = p[1], p[2], int(p[3][3:]), int(p[4][1:])
            raw[(arm, mode, rps, n)] = json.load(open(f))["latency_ms"]["p50"]
    med, diffs = {}, {}
    ns = sorted({k[3] for k in raw})
    for mode, rps in SPECS:
        for a in ARMS:
            med[(a, mode, rps)] = statistics.median(
                raw[(a, mode, rps, n)] for n in ns if (a, mode, rps, n) in raw)
        # 표의 정본과 같은 정의: 회차 안 인접 쌍 차이의 중앙값
        pairs = [n for n in ns if all((a, mode, rps, n) in raw for a in ARMS)]
        diffs[(mode, rps)] = (
            statistics.median(raw[("gwplain", mode, rps, n)] - raw[("direct", mode, rps, n)] for n in pairs),
            statistics.median(raw[("gwa2a", mode, rps, n)] - raw[("gwplain", mode, rps, n)] for n in pairs),
        )
    return med, diffs


def cost_chart(med, diffs, lang, path):
    t = T[lang]
    W, H = 860, 420
    x0, x1 = 250, 820
    vmax = 7.0
    sx = (x1 - x0) / vmax
    out = [f"<svg xmlns='http://www.w3.org/2000/svg' width='{W}' height='{H}' viewBox='0 0 {W} {H}'>",
           f"<rect width='{W}' height='{H}' fill='white'/>",
           f"<text x='24' y='34' {FONT} font-size='19' font-weight='bold' fill='{C['text']}'>{esc(t['cost_title'])}</text>",
           f"<text x='24' y='56' {FONT} font-size='12' fill='{C['sub']}'>{esc(t['cost_sub'])}</text>"]
    for g in range(0, 8):
        gx = x0 + g * sx
        out.append(f"<line x1='{gx:.0f}' y1='80' x2='{gx:.0f}' y2='{H-60}' stroke='{C['grid']}' stroke-width='1'/>")
        out.append(f"<text x='{gx:.0f}' y='{H-42}' {FONT} font-size='11' fill='{C['sub']}' text-anchor='middle'>{g}</text>")
    y = 110
    for mode, rps in SPECS:
        vals = {a: med[(a, mode, rps)] for a in ARMS}
        out.append(f"<text x='24' y='{y+5}' {FONT} font-size='13' font-weight='bold' fill='{C['text']}'>{esc(t['spec'](mode, rps))}</text>")
        xs = {a: x0 + vals[a] * sx for a in ARMS}
        out.append(f"<line x1='{xs['direct']:.0f}' y1='{y}' x2='{xs['gwa2a']:.0f}' y2='{y}' stroke='#999' stroke-width='2'/>")
        overlap = abs(xs["gwa2a"] - xs["gwplain"]) < 8
        if overlap:
            # 두 게이트웨이 경로가 같은 자리: gwplain을 고리로, gwa2a를 안에 채움
            out.append(f"<circle cx='{xs['direct']:.0f}' cy='{y}' r='7' fill='{C['direct']}'/>")
            out.append(f"<text x='{xs['direct']:.0f}' y='{y+26}' {FONT} font-size='11' fill='{C['direct']}' text-anchor='middle'>{vals['direct']:.1f}</text>")
            out.append(f"<circle cx='{xs['gwplain']:.0f}' cy='{y}' r='10' fill='white' stroke='{C['gwplain']}' stroke-width='3'/>")
            out.append(f"<circle cx='{xs['gwa2a']:.0f}' cy='{y}' r='5' fill='{C['gwa2a']}'/>")
            out.append(f"<text x='{xs['gwa2a']:.0f}' y='{y+28}' {FONT} font-size='11' fill='{C['text']}' text-anchor='middle'>{vals['gwa2a']:.1f}</text>")
        else:
            for a in ARMS:
                out.append(f"<circle cx='{xs[a]:.0f}' cy='{y}' r='7' fill='{C[a]}'/>")
                out.append(f"<text x='{xs[a]:.0f}' y='{y+26}' {FONT} font-size='11' fill='{C[a]}' text-anchor='middle'>{vals[a]:.1f}</text>")
        d1, d2 = diffs[(mode, rps)]
        mid1 = (xs["direct"] + xs["gwplain"]) / 2
        out.append(f"<text x='{mid1:.0f}' y='{y-14}' {FONT} font-size='11' fill='{C['sub']}' text-anchor='middle'>+{d1:.2f}</text>")
        if abs(d2) >= 0.3:
            mid2 = (xs["gwplain"] + xs["gwa2a"]) / 2
            out.append(f"<text x='{mid2:.0f}' y='{y-14}' {FONT} font-size='11' fill='{C['sub']}' text-anchor='middle'>+{d2:.2f}</text>")
        y += 62
    lx = 24
    for a in ARMS:
        out.append(f"<circle cx='{lx+6}' cy='{H-16}' r='6' fill='{C[a]}'/>")
        label = esc(t["arm"][a])
        out.append(f"<text x='{lx+18}' y='{H-11}' {FONT} font-size='12' fill='{C['text']}'>{label}</text>")
        lx += 18 + 9 * len(label) + 24
    out.append("</svg>")
    Path(path).write_text("\n".join(out))


def card_chart(lang, path):
    t = T[lang]
    W, H = 920, 386
    out = [f"<svg xmlns='http://www.w3.org/2000/svg' width='{W}' height='{H}' viewBox='0 0 {W} {H}'>",
           f"<rect width='{W}' height='{H}' fill='white'/>",
           f"<text x='24' y='34' {FONT} font-size='19' font-weight='bold' fill='{C['text']}'>{esc(t['card_title'])}</text>",
           f"<text x='24' y='56' {FONT} font-size='12' fill='{C['sub']}'>{esc(t['card_sub'])}</text>"]
    gx, gy, cw, ch = 310, 96, 260, 66
    for j, col in enumerate(t["cols"]):
        out.append(f"<text x='{gx+cw*j+cw/2:.0f}' y='{gy-10}' {FONT} font-size='13' font-weight='bold' fill='{C['text']}' text-anchor='middle'>{esc(col)}</text>")
    # 셀 내용: (행, 열) -> (배경, 본문 줄들)
    cell = {
        (0, 0): ("ok", [t["rewritten"]]),
        (1, 0): ("ok", [t["rewritten"]]),
        (2, 0): ("bad", [f"url: {t['kept']}", f"supportedInterfaces: {t['rewritten']}"]),
        (0, 1): ("bad", [t["kept"]]),
        (1, 1): ("bad", [t["kept"]]),
        (2, 1): ("bad", [t["kept"]]),
    }
    for i, row in enumerate(t["rows"]):
        cy = gy + ch * i
        out.append(f"<text x='{gx-14}' y='{cy+ch/2+4:.0f}' {FONT} font-size='12' fill='{C['text']}' text-anchor='end'>{esc(row)}</text>")
        for j in range(2):
            bg, lines = cell[(i, j)]
            cx = gx + cw * j
            extra = f" stroke='{C['badline']}' stroke-width='2'" if (i, j) == (2, 0) else f" stroke='#bbb' stroke-width='1'"
            out.append(f"<rect x='{cx+3}' y='{cy+3}' width='{cw-6}' height='{ch-6}' fill='{C[bg]}'{extra} rx='6'/>")
            ty = cy + ch / 2 + 4 - (len(lines) - 1) * 8
            for line in lines:
                out.append(f"<text x='{cx+cw/2:.0f}' y='{ty:.0f}' {FONT} font-size='11' fill='{C['text']}' text-anchor='middle'>{esc(line)}</text>")
                ty += 16
    # 누설 주석: 누설 셀 아래로 점선을 끌어내려 텍스트 연결
    lx = gx + cw / 2
    ly0 = gy + ch * 3
    out.append(f"<line x1='{lx:.0f}' y1='{ly0-3:.0f}' x2='{lx:.0f}' y2='{ly0+18:.0f}' stroke='{C['badline']}' stroke-width='2' stroke-dasharray='5,3'/>")
    for k, line in enumerate(t["leak"].split("\n")):
        out.append(f"<text x='{lx:.0f}' y='{ly0+34+16*k:.0f}' {FONT} font-size='12' font-weight='bold' fill='{C['badline']}' text-anchor='middle'>{esc(line)}</text>")
    out.append(f"<text x='24' y='{H-16}' {FONT} font-size='12' fill='{C['sub']}'>{esc(t['bypass'])}</text>")
    out.append("</svg>")
    Path(path).write_text("\n".join(out))


def main():
    bases = sys.argv[1:] or ["runs/rv-abm-0902"]
    med, diffs = load(bases)
    Path("figures").mkdir(exist_ok=True)
    for lang in ("en", "ko"):
        cost_chart(med, diffs, lang, f"figures/a2a-cost-3arm-{lang}.svg")
        card_chart(lang, f"figures/a2a-card-rewrite-{lang}.svg")
    print("figures/ 4장 생성")


if __name__ == "__main__":
    main()
