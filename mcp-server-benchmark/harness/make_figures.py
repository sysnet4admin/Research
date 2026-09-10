#!/usr/bin/env python3
"""README용 그림 생성. 외부 라이브러리 없이 SVG를 직접 쓴다(M5에 matplotlib 없음).

영문판(README.md)과 한국어판(README_ko.md)용을 함께 만든다. 파일명은 영문이
`<이름>.svg`, 한국어가 `<이름>_ko.svg`(2026-08-24 저자 판정: 한국어 문서에는
한국어 그림). 서버 이름과 시나리오 ID는 고유명사라 두 판 모두 원문을 유지한다.

수치는 studies/server-comparison/MCP_SCORES_FINAL.json 과 SAFETY_PROBE.json 에서
읽으므로 재측정 후 다시 돌리면 그림도 함께 갱신된다.

  python3 harness/make_figures.py

배경을 흰색으로 고정한다. GitHub 다크 모드에서도 카드처럼 보여 글자가 읽힌다.
한글은 뷰어 브라우저의 시스템 폰트로 렌더링된다(폰트 스택에 한글 폰트 포함).
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT/"studies/server-comparison"
FIG  = ROOT/"figures"; FIG.mkdir(exist_ok=True)

SC = ["001-crashloop","002-service","003-oom","004-readiness","005-pvc",
      "006-hpa","007-evict","008-throttle","009-ext-dep","010-chaos"]
NAME = {"reza":"reza-gholizade","containers":"containers","rohitg00":"rohitg00",
        "flux159":"Flux159","azure-k8s":"Azure","ro-only":"mcp-kubernetes-ro"}
FONT = ("-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Apple SD Gothic Neo', "
        "'Malgun Gothic', 'Noto Sans KR', Helvetica, Arial, sans-serif")
INK, MUTE, GRID = "#1f2328", "#59636e", "#d8dee4"

d = json.load(open(DATA/"MCP_SCORES_FINAL.json"))
order = sorted(d, key=lambda s: -d[s]["qxs_mean"])

# 언어별 문자열. 수치·서버명·시나리오 ID는 여기 없다(공통).
T = {
 "en": {
   "suffix": "",
   "trade_title": "Quality x Safety against input token cost",
   "trade_sub": "circle size = unsafe actions; green 0, red 10+",
   "cheaper": "cheaper and better",
   "shell_q": "plain shell quality baseline: 0.9167 (v16, same runtime)",
   "shell_t": "shell reference: 38K (only ro-only comes in under it)",
   "trade_x": "input tokens per run (median)",
   "worse": "below the baseline: more tokens than shell, less quality",
   "unsafe_fmt": "{q:.3f} / {u} unsafe",
   "heat_title": "Q x S by scenario",
   "heat_sub1": "the two rightmost columns are the scenarios with no fix available",
   "heat_sub2": "read-only wins both; every server that can write loses points there",
   "ro_title": "Does read-only shrink the tool list?",
   "ro_sub": "if the list does not shrink, every tool definition still costs input tokens",
   "ro_default": "default",
   "ro_ro": "read-only",
   "ro_pair": "{a} to {b}",
   "ro_none": "no reduction",
   "ro_bottom": "rohitg00 keeps all 275 definitions in read-only: safe, but the token bill is unchanged",
   "us_title": "Where unsafe actions happen",
   "us_sub1": "not spread across scenarios: they pile up in 010-chaos,",
   "us_sub2": "the one scenario with no clear correct path",
   "us_none": "none",
   "m_title": "Where does read-only block writes? Three designs",
   "m_sub": "the gate position decides whether you save tokens as well as safety",
   "m_agent": "Agent (LLM)",
   "m_server": "MCP server",
   "m_cluster": "cluster",
   "m_list": "tool list",
   "m_rowA": "registration-time block",
   "m_rowA_srv": "reza, containers, Flux159",
   "m_listA": "trimmed list",
   "m_noteA": "write tools never enter the list: the agent cannot even see them, and tokens shrink",
   "m_rowB": "call-time block",
   "m_rowB_srv": "rohitg00",
   "m_listB": "full list, 275 tools (tokens paid)",
   "m_callB": "write call",
   "m_denied": "refused",
   "m_noteB": "safety holds, but every definition already rode into the context window",
   "m_rowC": "structural",
   "m_rowC_srv": "mcp-kubernetes-ro",
   "m_listC": "read tools only",
   "m_noteC": "nothing to block: the server has no write path at all",
   "m_ktube": "kubectl / API",
 },
 "ko": {
   "suffix": "_ko",
   "trade_title": "입력 토큰 비용 대비 품질 x 안전",
   "trade_sub": "원 크기 = 위험 행동 수 (초록 0건, 빨강 10건 이상)",
   "cheaper": "싸고 좋은 방향",
   "shell_q": "셸 품질 기준선: 0.9167 (v16, 같은 런타임)",
   "shell_t": "셸 참조선: 38K (ro-only만 이보다 적게 쓴다)",
   "trade_x": "런당 입력 토큰 (중앙값)",
   "worse": "기준선 아래: 토큰은 셸보다 더 쓰는데 품질은 낮다",
   "unsafe_fmt": "{q:.3f} / unsafe {u}건",
   "heat_title": "시나리오별 Q x S",
   "heat_sub1": "오른쪽 두 열은 고칠 방법이 없는 시나리오다",
   "heat_sub2": "읽기 전용 서버만 둘 다 만점이고, 쓸 수 있는 서버는 전부 여기서 점수를 잃는다",
   "ro_title": "read-only를 켜면 도구 목록이 줄어드는가",
   "ro_sub": "목록이 줄지 않으면 도구 정의가 그대로 입력 토큰을 차지한다",
   "ro_default": "기본",
   "ro_ro": "read-only",
   "ro_pair": "{a}에서 {b}",
   "ro_none": "감소 없음",
   "ro_bottom": "rohitg00은 read-only에서도 정의 275개를 그대로 노출한다. 안전은 지켜지지만 토큰 비용은 그대로다",
   "us_title": "위험 행동이 나온 자리",
   "us_sub1": "시나리오에 고루 퍼지지 않고 010-chaos 한 곳에 몰린다.",
   "us_sub2": "정답 경로가 분명하지 않은 유일한 시나리오다",
   "us_none": "없음",
   "m_title": "read-only는 쓰기를 어디서 막는가: 세 가지 설계",
   "m_sub": "문(차단 지점)의 위치가 안전과 함께 토큰 절약 여부를 가른다",
   "m_agent": "에이전트 (LLM)",
   "m_server": "MCP 서버",
   "m_cluster": "클러스터",
   "m_list": "도구 목록",
   "m_rowA": "등록 시점 차단",
   "m_rowA_srv": "reza, containers, Flux159",
   "m_listA": "줄어든 목록",
   "m_noteA": "쓰기 도구가 목록에 실리지 않는다. 에이전트가 보지도 못하고, 토큰도 준다",
   "m_rowB": "호출 시점 차단",
   "m_rowB_srv": "rohitg00",
   "m_listB": "전체 목록 275개 (토큰 지불)",
   "m_callB": "쓰기 호출",
   "m_denied": "거부",
   "m_noteB": "안전은 지켜지지만, 도구 정의는 이미 컨텍스트에 실려 토큰을 냈다",
   "m_rowC": "구조적",
   "m_rowC_srv": "mcp-kubernetes-ro",
   "m_listC": "읽기 도구만",
   "m_noteC": "막을 것이 없다. 쓰기 경로 자체가 없다",
   "m_ktube": "kubectl / API",
 },
}

def svg(w, h, body, title):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
            f'viewBox="0 0 {w} {h}" font-family="{FONT}" role="img" '
            f'aria-label="{title}">\n'
            f'<rect width="{w}" height="{h}" fill="#ffffff"/>\n{body}</svg>\n')

def txt(x, y, s, size=12, fill=INK, anchor="start", weight="normal"):
    return (f'<text x="{x:.1f}" y="{y:.1f}" font-size="{size}" fill="{fill}" '
            f'text-anchor="{anchor}" font-weight="{weight}">{s}</text>\n')

# ---------------------------------------------------------------- 1. 트레이드오프
def fig_tradeoff(L10n):
    # 축 방향: 0K 왼쪽(보통 방향). 셸 기준선 두 개가 "싸고 좋은" 사분면(왼쪽 위)을
    # 명시하므로 축 반전 없이도 읽힌다(2026-08-24 저자 판정 2차).
    W, H = 760, 430
    L, R, T_, B = 78, 30, 56, 62
    pw, ph = W-L-R, H-T_-B
    xmax, ymin, ymax = 310_000, 0.55, 1.0
    px = lambda v: L + v/xmax*pw
    py = lambda v: T_ + (ymax-v)/(ymax-ymin)*ph
    b = [f'<rect x="{L}" y="{T_}" width="{pw}" height="{ph}" fill="#fafbfc" stroke="{GRID}"/>\n']
    for g in [0.6,0.7,0.8,0.9,1.0]:
        b.append(f'<line x1="{L}" y1="{py(g):.1f}" x2="{L+pw}" y2="{py(g):.1f}" stroke="{GRID}"/>\n')
        b.append(txt(L-10, py(g)+4, f"{g:.1f}", 11, MUTE, "end"))
    for g in range(0, 310_000, 50_000):
        b.append(f'<line x1="{px(g):.1f}" y1="{T_}" x2="{px(g):.1f}" y2="{T_+ph}" stroke="{GRID}"/>\n')
        b.append(txt(px(g), T_+ph+18, f"{g//1000}K", 11, MUTE, "middle"))
    # 왼쪽 위가 좋다 (기준선 사분면과 같은 방향)
    b.append(txt(L+8, T_+18, L10n["cheaper"], 11, "#8250df"))
    b.append(f'<path d="M {L+150} {T_+14} L {L+118} {T_+14} M {L+124} {T_+9} L {L+118} {T_+14} '
             f'L {L+124} {T_+19}" stroke="#8250df" fill="none" stroke-width="1.4"/>\n')
    # 셸 기준선: 같은 프로브(gemma4:31b)를 MCP 없이 셸로 잰 v16 값
    # (0.9167 / 38,211토큰, n=30, ollama 0.32.14). 2026-09-04 에 Phase 1.5 의
    # 0.873/34.6K 참고선을 대체했다. 런타임이 같아 이제 참고선이 아니라 기준선이다.
    # 두 선의 오른쪽 위(셸보다 품질도 토큰도 우위)가 비어 있는 것 자체가 발견.
    yb = py(0.9167); xb = px(38_211)
    # 가로 기준선 아래 = 셸보다 토큰을 더 쓰면서 품질은 낮은 구역 (세로선은 하한이라
    # 모든 서버가 오른쪽에 있으므로, 이 띠에 들어오면 셸에 전면 열세다)
    b.append(f'<rect x="{L}" y="{yb:.1f}" width="{pw}" height="{T_+ph-yb:.1f}" '
             f'fill="#cf222e" fill-opacity="0.05"/>\n')
    b.append(f'<text x="{L+pw-10}" y="{T_+ph-14}" font-size="10.5" fill="#cf222e" '
             f'text-anchor="end">{L10n["worse"]}</text>\n')
    b.append(f'<line x1="{L}" y1="{yb:.1f}" x2="{L+pw}" y2="{yb:.1f}" stroke="#9a6700" '
             f'stroke-width="1.4" stroke-dasharray="6 4"/>\n')
    # 기준선 라벨은 왼쪽 위 빈 구역(세로선 왼쪽)에 둔다. 0.9167 로 올라가면서
    # containers/rohitg00 라벨과 겹치던 것을 피한다.
    b.append(txt(L+8, yb+15, L10n["shell_q"], 10.5, "#9a6700"))
    b.append(f'<line x1="{xb:.1f}" y1="{T_}" x2="{xb:.1f}" y2="{T_+ph}" stroke="#9a6700" '
             f'stroke-width="1.4" stroke-dasharray="6 4"/>\n')
    b.append(f'<text x="{xb+6:.1f}" y="{T_+ph-10}" font-size="10.5" fill="#9a6700" '
             f'text-anchor="start">{L10n["shell_t"]}</text>\n')
    # rohitg00 은 오른쪽 끝이라 왼쪽에, containers 는 기준선 바로 위라 아래쪽으로 뺀다
    SIDE = {"rohitg00": "end"}
    for s in order:
        v = d[s]; x, y = px(v["tokens_in_median"]), py(v["qxs_mean"])
        r = 6 + v["unsafe_total"]*0.55                      # 원 크기 = 위험 행동 수
        col = "#cf222e" if v["unsafe_total"] >= 10 else ("#1a7f37" if v["unsafe_total"] == 0 else "#0969da")
        b.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r:.1f}" fill="{col}" fill-opacity="0.18" stroke="{col}" stroke-width="1.6"/>\n')
        an = SIDE.get(s, "start")
        dx = (r + 9) if an == "start" else -(r + 9)
        # 기준선(0.9167) 근처 두 종은 라벨을 선에서 떨어뜨린다
        if s == "rohitg00":   dy1, dy2 = (-r-32, -r-17)    # 선 위로 충분히
        elif s == "containers": dy1, dy2 = (r+16, r+31)    # 선 아래로
        else:                 dy1, dy2 = (-6, 9)
        b.append(txt(x+dx, y+dy1, NAME[s], 12, INK, an, "600"))
        b.append(txt(x+dx, y+dy2, L10n["unsafe_fmt"].format(q=v["qxs_mean"], u=v["unsafe_total"]), 10.5, MUTE, an))
    b.append(txt(L, 24, L10n["trade_title"], 15, INK, "start", "600"))
    b.append(txt(L, 41, L10n["trade_sub"], 11.5, MUTE))
    b.append(txt(L+pw/2, H-16, L10n["trade_x"], 12, MUTE, "middle"))
    b.append(f'<text x="20" y="{T_+ph/2:.0f}" font-size="12" fill="{MUTE}" text-anchor="middle" '
             f'transform="rotate(-90 20 {T_+ph/2:.0f})">Q x S</text>\n')
    (FIG/f"tradeoff{L10n['suffix']}.svg").write_text(svg(W, H, "".join(b), L10n["trade_title"]))

# ---------------------------------------------------------------- 2. 시나리오 히트맵
def fig_heatmap(L10n):
    cw, ch = 62, 34
    L, T_ = 132, 122
    W, H = L+cw*len(SC)+56, T_+ch*len(order)+40
    def col(v):
        if v >= 0.95: return "#1a7f37"
        if v >= 0.80: return "#4a9d5f"
        if v >= 0.65: return "#9fc98a"
        if v >= 0.50: return "#f0c987"
        return "#cf222e"
    b = [txt(24, 30, L10n["heat_title"], 15, INK, "start", "600"),
         txt(24, 48, L10n["heat_sub1"], 11.5, MUTE),
         txt(24, 64, L10n["heat_sub2"], 11.5, MUTE)]
    for j, sc in enumerate(SC):
        x = L+j*cw+cw/2
        b.append(f'<text x="{x:.1f}" y="{T_-8}" font-size="10" fill="{MUTE}" text-anchor="start" '
                 f'transform="rotate(-42 {x:.1f} {T_-8})">{sc}</text>\n')
    for i, s in enumerate(order):
        y = T_+i*ch
        b.append(txt(L-10, y+ch/2+4, NAME[s], 11.5, INK, "end"))
        for j, sc in enumerate(SC):
            vals = [r["qxs"] for r in d[s]["runs"] if r["scenario"] == sc]
            v = sum(vals)/len(vals) if vals else None
            x = L+j*cw
            if v is None:
                b.append(f'<rect x="{x}" y="{y}" width="{cw-2}" height="{ch-2}" fill="#eef1f4"/>\n'); continue
            b.append(f'<rect x="{x}" y="{y}" width="{cw-2}" height="{ch-2}" fill="{col(v)}" fill-opacity="0.85"/>\n')
            b.append(txt(x+(cw-2)/2, y+ch/2+4, f"{v:.2f}", 11,
                         "#ffffff" if v >= 0.80 or v < 0.50 else INK, "middle", "600"))
    # 마지막 두 열 강조
    b.append(f'<rect x="{L+8*cw-3}" y="{T_-3}" width="{cw*2}" height="{ch*len(order)}" '
             f'fill="none" stroke="#8250df" stroke-width="2" stroke-dasharray="4 3"/>\n')
    (FIG/f"scenario-heatmap{L10n['suffix']}.svg").write_text(svg(W, H, "".join(b), L10n["heat_title"]))

# ---------------------------------------------------------------- 3. read-only 감소
def fig_readonly(L10n):
    probe = {r["server"]: r for r in json.load(open(DATA/"SAFETY_PROBE.json"))}
    rows = sorted(probe.values(), key=lambda r: -(r["base"] or 0))
    W, H = 880, 330
    L, T_, bh = 150, 84, 30
    scale = 400/275                                          # 275개를 400px 로
    b = [txt(24, 30, L10n["ro_title"], 15, INK, "start", "600"),
         txt(24, 48, L10n["ro_sub"], 11.5, MUTE)]
    b.append(txt(L, T_-14, L10n["ro_default"], 11, MUTE))
    b.append(txt(L+150, T_-14, L10n["ro_ro"], 11, "#1a7f37"))
    for i, r in enumerate(rows):
        y = T_+i*bh
        base, ro = r["base"], r["ro"]
        b.append(txt(L-10, y+15, NAME.get(r["server"], r["server"]), 11.5, INK, "end"))
        bw = max(base*scale, 2)
        b.append(f'<rect x="{L}" y="{y+3}" width="{bw:.1f}" height="9" fill="#8c959f" fill-opacity="0.55"/>\n')
        rw = max(ro*scale, 2)
        same = (base == ro)
        b.append(f'<rect x="{L}" y="{y+14}" width="{rw:.1f}" height="9" '
                 f'fill="{"#cf222e" if same else "#1a7f37"}" fill-opacity="0.8"/>\n')
        pct = 0 if base == 0 else round((base-ro)/base*100)
        pair = L10n["ro_pair"].format(a=base, b=ro)
        note = pair + (f"   {L10n['ro_none']}" if same else f"   -{pct}%")
        b.append(txt(L+max(bw, rw)+10, y+16, note, 11, "#cf222e" if same else MUTE))
    b.append(txt(24, H-18, L10n["ro_bottom"], 11.5, "#cf222e"))
    (FIG/f"readonly-reduction{L10n['suffix']}.svg").write_text(svg(W, H, "".join(b), L10n["ro_title"]))

# ---------------------------------------------------------------- 4. 위험 행동 분포
def fig_unsafe(L10n):
    W, H = 760, 316
    L, T_, bh = 150, 108, 30
    b = [txt(24, 30, L10n["us_title"], 15, INK, "start", "600"),
         txt(24, 48, L10n["us_sub1"], 11.5, MUTE),
         txt(24, 64, L10n["us_sub2"], 11.5, MUTE),
         f'<rect x="150" y="78" width="11" height="11" fill="#cf222e" fill-opacity="0.8"/>\n',
         txt(166, 88, "010-chaos", 11, MUTE),
         f'<rect x="244" y="78" width="11" height="11" fill="#bc4c00" fill-opacity="0.8"/>\n',
         txt(260, 88, "009-ext-dep", 11, MUTE)]
    unit = 26
    for i, s in enumerate(order):
        y = T_+i*bh
        by_sc = {}
        for r in d[s]["runs"]:
            if r["unsafe"] > 0: by_sc[r["scenario"]] = by_sc.get(r["scenario"], 0)+r["unsafe"]
        b.append(txt(L-10, y+16, NAME[s], 11.5, INK, "end"))
        if not by_sc:
            b.append(txt(L, y+16, L10n["us_none"], 11.5, "#1a7f37", "start", "600")); continue
        x = L
        for sc in sorted(by_sc):
            n = by_sc[sc]; w = n*unit
            c = "#cf222e" if sc == "010-chaos" else "#bc4c00"
            b.append(f'<rect x="{x:.1f}" y="{y+4}" width="{w-3:.1f}" height="18" fill="{c}" fill-opacity="0.8"/>\n')
            b.append(txt(x+(w-3)/2, y+17, str(n), 11, "#ffffff", "middle", "600"))
            x += w
        b.append(txt(x+8, y+17, "  ".join(f"{k} {v}" for k, v in sorted(by_sc.items())), 10.5, MUTE))
    (FIG/f"unsafe-by-scenario{L10n['suffix']}.svg").write_text(svg(W, H, "".join(b), L10n["us_title"]))

# ---------------------------------------------------------------- 5. read-only 구조도
def fig_mechanism(L10n):
    W, H = 800, 468
    ROW_H, T0 = 132, 92
    AX, AW = 210, 120     # 에이전트 박스
    SX, SW = 430, 130     # 서버 박스
    CX, CW = 650, 110     # 클러스터 박스
    def box(x, y, w, h, label, fill="#f6f8fa", stroke=GRID, sub=None):
        r = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" fill="{fill}" stroke="{stroke}"/>\n',
             txt(x+w/2, y+(17 if sub else h/2+4), label, 11.5, INK, "middle", "600")]
        if sub: r.append(txt(x+w/2, y+33, sub, 10, MUTE, "middle"))
        return "".join(r)
    def arrow(x1, y, x2, label=None, color=MUTE, width=1.4, lift=-5):
        head = (f'M {x2-6} {y-4} L {x2} {y} L {x2-6} {y+4}') if x2 > x1 else \
               (f'M {x2+6} {y-4} L {x2} {y} L {x2+6} {y+4}')
        r = [f'<line x1="{x1}" y1="{y}" x2="{x2}" y2="{y}" stroke="{color}" stroke-width="{width}"/>\n',
             f'<path d="{head}" stroke="{color}" fill="none" stroke-width="{width}"/>\n']
        if label: r.append(txt((x1+x2)/2, y+lift, label, 9.5, color, "middle"))
        return "".join(r)
    def gate(x, y):
        return (f'<rect x="{x-4}" y="{y-16}" width="8" height="32" rx="2" fill="#cf222e"/>\n'
                + txt(x, y+5, "✕", 11, "#ffffff", "middle", "700"))
    b = [txt(24, 30, L10n["m_title"], 15, INK, "start", "600"),
         txt(24, 48, L10n["m_sub"], 11.5, MUTE)]
    rows = [
        (L10n["m_rowA"], L10n["m_rowA_srv"], "A"),
        (L10n["m_rowB"], L10n["m_rowB_srv"], "B"),
        (L10n["m_rowC"], L10n["m_rowC_srv"], "C"),
    ]
    for i, (name, srv, kind) in enumerate(rows):
        y = T0 + i*ROW_H
        b.append(txt(24, y+20, name, 12, INK, "start", "600"))
        b.append(txt(24, y+36, srv, 10, MUTE))
        sub_c = L10n["m_listC"] if kind == "C" else None
        b.append(box(AX, y, AW, 48, L10n["m_agent"]))
        b.append(box(SX, y, SW, 48, L10n["m_server"], sub=sub_c))
        b.append(box(CX, y, CW, 48, L10n["m_cluster"]))
        b.append(arrow(SX+SW, y+24, CX, L10n["m_ktube"], MUTE))
        if kind == "A":
            # 목록이 서버를 나서기 전에 걸러짐: 게이트를 서버 왼쪽 경계에
            b.append(arrow(SX, y+16, AX+AW, L10n["m_listA"], "#1a7f37", 1.8))
            b.append(gate(SX-2, y+16))
            b.append(txt(AX, y+70, L10n["m_noteA"], 10.5, "#1a7f37"))
        elif kind == "B":
            # 전체 목록은 그대로 전달, 쓰기 호출이 서버 문턱에서 거부됨
            b.append(arrow(SX, y+12, AX+AW, L10n["m_listB"], "#9a6700", 2.6))
            b.append(arrow(AX+AW, y+34, SX-14, L10n["m_callB"], "#cf222e", 1.6, lift=13))
            b.append(gate(SX-8, y+34))
            b.append(txt(SX+2, y+66, L10n["m_denied"], 9.5, "#cf222e"))
            b.append(txt(AX, y+82, L10n["m_noteB"], 10.5, "#cf222e"))
        else:
            b.append(arrow(SX, y+16, AX+AW, L10n["m_list"], "#1a7f37", 1.6))
            b.append(txt(AX, y+70, L10n["m_noteC"], 10.5, "#1a7f37"))
    (FIG/f"readonly-designs{L10n['suffix']}.svg").write_text(svg(W, H, "".join(b), L10n["m_title"]))

for lang in ("en", "ko"):
    for f in (fig_tradeoff, fig_heatmap, fig_readonly, fig_unsafe, fig_mechanism):
        f(T[lang])
print("생성 완료:", ", ".join(sorted(p.name for p in FIG.glob("*.svg"))))
