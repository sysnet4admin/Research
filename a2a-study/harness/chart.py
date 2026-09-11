#!/usr/bin/env python3
"""a2a-study 발행용 SVG 생성. 두 언어판을 같은 코드에서 낸다.

사용: python3 harness/chart.py <kind> <lang> > figures/<kind>-<lang>.svg
  kind: surface   Q1의 "보이는 것은 넷뿐" 도식
        compare   Q4의 "MCP와 A2A는 상대가 다르다" 비교표
        result    결과 절의 "얻는 것과 드는 것" 한눈 비교
  lang: ko | en

agentgateway-study/harness/chart.py와 같은 구조다(텍스트 카탈로그 + 함수 하나당
그림 하나 + 표준 출력). 수치 그림이 아니라 개념 도식이므로 runs를 읽지 않는다.
"""
import sys
import unicodedata

TEXT = {
    "ko": {
        "title": "상대는 불투명하고 보이는 것은 넷뿐이다",
        "sub": "A2A가 정한 것은 이 넷과 이들을 나르는 전송 규칙이다.",
        "me": "내 에이전트",
        "panel": "보이는 것",
        "peer": "상대 에이전트",
        "peer_note": "보이지 않는다",
        "hidden": ["도구", "메모리", "모델", "내부 계획"],
        "b1t": "① 카드", "b1s": "Agent Card",
        "b1n": "누구이고 무엇을 하는가\n어디로 어떻게 부르는가",
        "b2t": "② 메시지", "b2s": "Message",
        "b2n": "보내는 내용\n텍스트, 파일, 구조화 데이터",
        "b3t": "③ 태스크", "b3s": "Task",
        "b3n": "일의 단위\nid, 상태, 이력, 산출물",
        "b4t": "④ 아티팩트", "b4s": "Artifact",
        "b4n": "태스크가 만든 결과",
        "r12": "어디로 보낼지 알려 준다",
        "r23": "보내면 생긴다",
        "r34": "끝나면 남는다",
        "a_me": "카드를 받고 메시지를 보낸다",
        "a_peer": "일을 맡는다",
        "cap": "이 연구가 확인하는 것은 이 넷이 스펙대로 동작하는가이다. 카드의 선언이 실제로 강제되는가(선언 대 실제),"
               " 태스크가 있어서 HTTP나 MCP로 만들 때와 무엇이 달라지는가(대안 대비).",
        "c_title": "MCP와 A2A는 상대가 다르다",
        "c_sub": "겹치는 자리가 없어서 하는 일에 따라 골라 쓴다.",
        "c_left": "MCP", "c_right": "A2A",
        "c_rows": [
            ("상대", "도구와 자원", "다른 에이전트"),
            ("모델", "부르면 결과가 온다", "일을 받아 시간을 들여 처리한다\n중간에 묻거나 거절할 수 있다"),
            ("있는 것", "도구 목록(tools/list)\n도구 호출(tools/call)",
             "카드, 태스크\n상태 변화(조회, 구독, 푸시), 취소"),
            ("없는 것", "진행 중인 일의 상태\n중간 입력 요청, 취소", "도구 목록이라는 개념"),
        ],
        "c_band": "무엇을 하려느냐에 따라 고른다",
        "c_t1": "내 에이전트", "c_t2": "상대 에이전트", "c_t3": "도구와 자원",
        "c_e1": "도구를 직접 쓴다", "c_e2": "남에게 일을 맡긴다",
        "c_e3": "자기 도구는 MCP로",
        "c_cap": "둘은 순서가 아니라 선택이다. 도구를 직접 쓰면 MCP만 있으면 되고 남에게 일을 맡길 때 A2A를 쓴다."
                 " 맡은 쪽이 자기 도구를 부르는 것은 그쪽 사정이고 내가 거쳐 가는 경로가 아니다.",
        "r_title": "얻는 것과 드는 것",
        "r_sub": "같은 작업을 세 가지로 만들어 비교했다. 칸마다 조건이 다르고 셋 다 낮을수록 좋다.",
        "r_p1": "상대가 바뀌면 다시 만들 항목",
        "r_p1u": "개", "r_p1n": "A2A만 스펙이 정해 준다",
        "r_p2": "응답 1건당 바이트",
        "r_p2u": "B", "r_p2n": "부하 없이 단발 호출 1회",
        "r_p3": "호출당 지연 p50",
        "r_p3u": "ms", "r_p3n": "100rps, 연결 재사용",
        "r_cap": "왼쪽이 얻는 것이고 오른쪽 둘이 드는 것이다. 파란 막대가 왼쪽에서는 가장 짧고 오른쪽에서는 가장 길다."
                 " 바이트가 큰 것은 태스크 객체를 매번 싣기 때문이다. 짧은 단발 호출이라면 왼쪽에서 얻을 것이 없어 비용만 남는다.",
    },
    "en": {
        "title": "The counterpart is opaque; only four things are visible",
        "sub": "What A2A fixes is these four, plus the transport that carries them.",
        "me": "my agent",
        "panel": "what is visible",
        "peer": "the other agent",
        "peer_note": "not visible",
        "hidden": ["tools", "memory", "model", "internal plan"],
        "b1t": "1. Card", "b1s": "Agent Card",
        "b1n": "who it is and what it does\nwhere and how to call it",
        "b2t": "2. Message", "b2s": "Message",
        "b2n": "what you send\ntext, files, structured data",
        "b3t": "3. Task", "b3s": "Task",
        "b3n": "the unit of work\nid, state, history, artifacts",
        "b4t": "4. Artifact", "b4s": "Artifact",
        "b4n": "what the task produced",
        "r12": "tells you where to send",
        "r23": "sending one creates it",
        "r34": "left behind when it ends",
        "a_me": "fetches the card, sends a message",
        "a_peer": "takes the work",
        "cap": "What this study measures is whether these four behave as specified: whether the card's"
               " declarations are enforced, and what having a task changes compared with"
               " building the same thing over HTTP or MCP.",
        "c_title": "MCP and A2A differ in what sits on the other end",
        "c_sub": "They do not overlap, so you pick by what you are doing.",
        "c_left": "MCP", "c_right": "A2A",
        "c_rows": [
            ("the other end", "tools and resources", "another agent"),
            ("the model", "call it, a result comes back",
             "takes work and spends time on it\nmay ask a question or refuse"),
            ("what it has", "tool listing (tools/list)\ntool calls (tools/call)",
             "cards, tasks\nstate changes (get, subscribe, push), cancel"),
            ("what it lacks", "state of work in flight\nmid-flight input, cancellation",
             "any notion of a tool list"),
        ],
        "c_band": "pick by what you are doing",
        "c_t1": "my agent", "c_t2": "the other agent", "c_t3": "tools and resources",
        "c_e1": "use a tool yourself", "c_e2": "hand work to someone else",
        "c_e3": "its own tools, MCP",
        "c_cap": "These are a choice, not a sequence. Using a tool yourself needs only MCP; A2A is for handing work to someone else."
                 " That the other agent calls its own tools is its business, not a leg of your path.",
        "r_title": "What you get and what you pay",
        "r_sub": "The same job built three ways. Each panel has its own conditions; lower is better in all three.",
        "r_p1": "items to rebuild per counterpart",
        "r_p1u": "", "r_p1n": "only A2A has the spec fix them",
        "r_p2": "bytes per response",
        "r_p2u": "B", "r_p2n": "one call, no load",
        "r_p3": "latency per call, p50",
        "r_p3u": "ms", "r_p3n": "100 rps, connection reuse",
        "r_cap": "The left panel is what you get; the two on the right are what you pay. The blue bar is the shortest on the left"
                 " and the longest on the right. The bytes are high because the task object rides along every time. For short one-shot calls"
                 " there is nothing to gain on the left, so only the cost remains.",
    },
}

W, H = 900, 470


def esc(t):
    return t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def txt(x, y, s, size=12, fill="#222", anchor="middle", bold=False, mono=False):
    f = ' font-weight="bold"' if bold else ""
    m = ' font-family="Menlo, monospace"' if mono else ""
    return (f'<text x="{x}" y="{y}" font-size="{size}" fill="{fill}" '
            f'text-anchor="{anchor}"{f}{m}>{esc(s)}</text>')


def multiline(x, y, s, size=10, fill="#666", step=14):
    return [txt(x, y + i * step, line, size, fill) for i, line in enumerate(s.split("\n"))]


def box(x, y, w, h, fill="#fafafa", stroke="#999", dash="", rx=6, sw=1.5):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" '
            f'stroke="{stroke}" stroke-width="{sw}"{d}/>')


def line_label(x, y, text, size=8.5, fill="#777"):
    """화살표 위에 얹는 짧은 설명. 상자와 겹쳐도 읽히도록 흰 바탕을 깐다."""
    w = dwidth(text) * size * 0.55 + 8
    return [f'<rect x="{x - w / 2}" y="{y - size - 1}" width="{w}" height="{size + 5}" fill="white"/>',
            txt(x, y, text, size, fill)]


def arrow(x1, y1, x2, y2, color="#555", sw=1.8, dash=""):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    return (f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" '
            f'stroke-width="{sw}" marker-end="url(#a)"{d}/>')


def surface(T):
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" '
         f'font-family="Helvetica, Arial, sans-serif">',
         f'<rect width="{W}" height="{H}" fill="white"/>',
         '<defs><marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" '
         'markerHeight="6" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="#555"/></marker></defs>']

    s.append(txt(W / 2, 32, T["title"], 15, "#111", bold=True))
    s.append(txt(W / 2, 52, T["sub"], 11, "#777"))

    # 내 에이전트
    s.append(box(30, 210, 130, 58))
    s.append(txt(95, 238, T["me"], 12, "#222", bold=True))
    s.extend(multiline(95, 286, wrapcap(T["a_me"], 24), 8.5, "#888", 12))

    # 가운데 패널
    px, py, pw, ph = 196, 80, 452, 274
    s.append(box(px, py, pw, ph, fill="#ffffff", stroke="#326CE5", sw=1.6))
    s.append(f'<rect x="{px}" y="{py}" width="{pw}" height="26" rx="6" fill="#326CE5"/>')
    s.append(f'<rect x="{px}" y="{py + 16}" width="{pw}" height="10" fill="#326CE5"/>')
    s.append(txt(px + pw / 2, py + 18, T["panel"], 11.5, "#ffffff", bold=True))

    bw, bh = 180, 76
    cols = [px + 14, px + 14 + bw + 64]
    rows = [py + 40, py + 40 + bh + 54]
    items = [("b1t", "b1s", "b1n"), ("b2t", "b2s", "b2n"),
             ("b3t", "b3s", "b3n"), ("b4t", "b4s", "b4n")]
    # 시계 방향으로 돈다. 카드(왼쪽 위) -> 메시지(오른쪽 위) -> 태스크(오른쪽 아래)
    # -> 아티팩트(왼쪽 아래). 화살표가 곧 일이 진행되는 순서다.
    slots = [(cols[0], rows[0]), (cols[1], rows[0]),
             (cols[1], rows[1]), (cols[0], rows[1])]
    pos = []
    for i, (kt, ks, kn) in enumerate(items):
        x, y = slots[i]
        pos.append((x, y))
        s.append(box(x, y, bw, bh))
        s.append(txt(x + bw / 2, y + 20, T[kt], 12.5, "#222", bold=True))
        s.append(txt(x + bw / 2, y + 34, T[ks], 9, "#8a8a8a", mono=True))
        s.extend(multiline(x + bw / 2, y + 50, T[kn], 9.5, "#666", 12))

    # 관계 화살표
    (x1, y1), (x2, y2), (x3, y3), (x4, y4) = pos
    s.append(arrow(x1 + bw + 4, y1 + bh / 2, x2 - 6, y2 + bh / 2))
    s.extend(line_label((x1 + bw + x2) / 2, y1 + bh / 2 - 7, T["r12"]))
    s.append(arrow(x2 + bw / 2, y2 + bh + 4, x2 + bw / 2, y3 - 6))
    s.extend(line_label(x2 + bw / 2, (y2 + bh + y3) / 2 + 3, T["r23"]))
    s.append(arrow(x3 - 6, y3 + bh / 2, x4 + bw + 4, y4 + bh / 2))
    s.extend(line_label((x4 + bw + x3) / 2, y3 + bh / 2 - 7, T["r34"]))

    # 상대 에이전트 (불투명)
    qx, qy, qw, qh = 706, 158, 170, 182
    s.append(box(qx, qy, qw, qh, fill="#f4f4f4", stroke="#bbb", dash="6 4"))
    s.append(txt(qx + qw / 2, qy + 22, T["peer"], 12, "#555", bold=True))
    s.append(txt(qx + qw / 2, qy + 38, T["a_peer"], 9, "#999"))
    for i, h in enumerate(T["hidden"]):
        hy = qy + 52 + i * 26
        s.append(box(qx + 20, hy, qw - 40, 20, fill="#e9e9e9", stroke="#dcdcdc", rx=4, sw=1))
        s.append(txt(qx + qw / 2, hy + 14, h, 9.5, "#999"))
    s.append(txt(qx + qw / 2, qy + qh - 8, T["peer_note"], 9.5, "#999"))

    # 좌우 연결
    s.append(arrow(160, 239, px - 6, 239))
    s.append(arrow(px + pw + 6, 240, qx - 6, 240))

    s.extend(multiline(W / 2, H - 46, wrapcap(T["cap"], 158), 10, "#555", 15))
    s.append("</svg>")
    return "\n".join(s)


def dwidth(s):
    """표시 너비. 한글과 한자는 두 칸을 차지하므로 글자 수로 감싸면 어긋난다."""
    return sum(2 if unicodedata.east_asian_width(c) in ("W", "F") else 1 for c in s)


def compare(T):
    w, h = 900, 548
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" '
         f'font-family="Helvetica, Arial, sans-serif">',
         f'<rect width="{w}" height="{h}" fill="white"/>',
         '<defs><marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" '
         'markerHeight="6" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="#555"/></marker></defs>']
    s.append(txt(w / 2, 32, T["c_title"], 15, "#111", bold=True))
    s.append(txt(w / 2, 52, T["c_sub"], 11, "#777"))

    # 비교표. 왼쪽 좁은 열이 항목 이름, 가운데가 MCP, 오른쪽이 A2A.
    tx, ty = 56, 78
    c0, c1, c2 = 118, 335, 335
    hh, rh = 32, 54
    s.append(box(tx, ty, c0 + c1 + c2, hh + rh * 4, fill="#ffffff", stroke="#ccc", sw=1.2))
    # 머리글
    s.append(f'<rect x="{tx + c0}" y="{ty}" width="{c1}" height="{hh}" fill="#eef1f6"/>')
    s.append(f'<rect x="{tx + c0 + c1}" y="{ty}" width="{c2}" height="{hh}" fill="#326CE5"/>')
    s.append(txt(tx + c0 + c1 / 2, ty + 21, T["c_left"], 13, "#3c4655", bold=True))
    s.append(txt(tx + c0 + c1 + c2 / 2, ty + 21, T["c_right"], 13, "#ffffff", bold=True))
    # 세로 구분선
    for gx in (tx + c0, tx + c0 + c1):
        s.append(f'<line x1="{gx}" y1="{ty}" x2="{gx}" y2="{ty + hh + rh * 4}" '
                 f'stroke="#ddd" stroke-width="1"/>')
    for i, (name, left, right) in enumerate(T["c_rows"]):
        ry = ty + hh + rh * i
        if i:
            s.append(f'<line x1="{tx}" y1="{ry}" x2="{tx + c0 + c1 + c2}" y2="{ry}" '
                     f'stroke="#eee" stroke-width="1"/>')
        s.append(f'<rect x="{tx}" y="{ry}" width="{c0}" height="{rh}" fill="#fafafa"/>')
        s.append(txt(tx + c0 / 2, ry + rh / 2 + 4, name, 11, "#555", bold=True))
        for col, text in ((tx + c0 + c1 / 2, left), (tx + c0 + c1 + c2 / 2, right)):
            lines = text.split("\n")
            top = ry + rh / 2 + 4 - (len(lines) - 1) * 7
            for li, ln in enumerate(lines):
                s.append(txt(col, top + li * 14, ln, 10.5, "#333"))

    # 아래 띠: 갈림길. 일렬로 그리면 "A2A를 거쳐야 MCP에 닿는다"로 읽힌다.
    by = ty + hh + rh * 4 + 34
    bh_band = 140
    s.append(txt(tx, by - 6, T["c_band"], 11, "#777", anchor="start", bold=True))
    s.append(box(tx, by, c0 + c1 + c2, bh_band, fill="#fbfcfe", stroke="#dde3ee"))

    bw2, bh2 = 150, 40
    x_me = tx + 26
    x_stem = tx + 220
    x_mid = tx + 330
    x_far = tx + 560
    y_top = by + 26
    y_bot = by + 80
    y_me = (y_top + y_bot) / 2

    # 내 에이전트
    s.append(box(x_me, y_me, bw2, bh2))
    s.append(txt(x_me + bw2 / 2, y_me + bh2 / 2 + 4, T["c_t1"], 11.5, "#333", bold=True))

    # 갈래 1. 도구를 직접 쓴다 (MCP)
    s.append(box(x_mid, y_top, bw2, bh2, fill="#f2f2f2"))
    s.append(txt(x_mid + bw2 / 2, y_top + bh2 / 2 + 4, T["c_t3"], 11.5, "#333", bold=True))
    s.append(f'<path d="M{x_me + bw2 + 6},{y_me + bh2 / 2} H{x_stem} '
             f'V{y_top + bh2 / 2} H{x_mid - 8}" fill="none" stroke="#7b8ca5" '
             f'stroke-width="1.8" marker-end="url(#a)"/>')
    s.extend(line_label((x_stem + x_mid) / 2, y_top + bh2 / 2 - 9,
                        "MCP: " + T["c_e1"], 9))

    # 갈래 2. 남에게 일을 맡긴다 (A2A)
    s.append(box(x_mid, y_bot, bw2, bh2, fill="#fafafa", stroke="#326CE5"))
    s.append(txt(x_mid + bw2 / 2, y_bot + bh2 / 2 + 4, T["c_t2"], 11.5, "#333", bold=True))
    s.append(f'<path d="M{x_me + bw2 + 6},{y_me + bh2 / 2} H{x_stem} '
             f'V{y_bot + bh2 / 2} H{x_mid - 8}" fill="none" stroke="#326CE5" '
             f'stroke-width="1.8" marker-end="url(#a)"/>')
    s.extend(line_label((x_stem + x_mid) / 2, y_bot + bh2 / 2 - 9,
                        "A2A: " + T["c_e2"], 9))

    # 상대가 자기 도구를 부르는 것은 그쪽 사정이다. 점선으로 낮춰 그린다.
    s.append(box(x_far, y_bot, bw2, bh2, fill="#f7f7f7", stroke="#dcdcdc", dash="5 4"))
    s.append(txt(x_far + bw2 / 2, y_bot + bh2 / 2 + 4, T["c_t3"], 11, "#999"))
    s.append(arrow(x_mid + bw2 + 6, y_bot + bh2 / 2, x_far - 8, y_bot + bh2 / 2,
                   color="#bbb", sw=1.4, dash="4 3"))
    s.extend(line_label((x_mid + bw2 + x_far) / 2, y_bot + bh2 / 2 - 8, T["c_e3"], 8.5, "#999"))

    s.extend(multiline(w / 2, h - 32, wrapcap(T["c_cap"], 158), 10, "#555", 15))
    s.append("</svg>")
    return "\n".join(s)


def result(T):
    """결과 절의 한눈 비교. 얻는 것 하나와 드는 것 둘을 같은 형태의 막대로 놓아
    트레이드오프가 한 화면에 보이게 한다. 색은 프로토콜마다 고정한다."""
    w, h = 900, 400
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" '
         f'font-family="Helvetica, Arial, sans-serif">',
         f'<rect width="{w}" height="{h}" fill="white"/>']
    s.append(txt(w / 2, 32, T["r_title"], 15, "#111", bold=True))
    s.append(txt(w / 2, 52, T["r_sub"], 11, "#777"))

    arms = [("HTTP", "#b6bec7"), ("MCP", "#7b8ca5"), ("A2A", "#326CE5")]
    panels = [
        (T["r_p1"], T["r_p1u"], T["r_p1n"], [5, 5, 0], "{:.0f}"),
        (T["r_p2"], T["r_p2u"], T["r_p2n"], [80, 286, 581], "{:.0f}"),
        (T["r_p3"], T["r_p3u"], T["r_p3n"], [3.0, 4.1, 4.4], "{:.1f}"),
    ]
    pw, gap, px0, py = 268, 20, 22, 84
    for pi, (name, unit, note, vals, fmt) in enumerate(panels):
        x = px0 + pi * (pw + gap)
        s.append(box(x, py, pw, 236, fill="#ffffff", stroke="#e2e6ec", sw=1.2))
        s.append(txt(x + pw / 2, py + 26, name, 11.5, "#333", bold=True))
        s.append(txt(x + pw / 2, py + 43, note, 9, "#999"))
        top = py + 66
        lab_w, val_w = 46, 56
        bar_x = x + 14 + lab_w
        bar_max = pw - 28 - lab_w - val_w
        vmax = max(vals) or 1
        for ai, ((arm, color), v) in enumerate(zip(arms, vals)):
            by = top + ai * 48
            s.append(txt(x + 14 + lab_w - 8, by + 16, arm, 10.5, "#555", anchor="end"))
            s.append(f'<rect x="{bar_x}" y="{by + 4}" width="{bar_max}" height="16" rx="3" fill="#f4f6f8"/>')
            # 값이 0이면 막대를 그리지 않는다. 최소 너비를 주면 0이 아닌 것처럼 보인다.
            if v > 0:
                bl = max(3, bar_max * v / vmax)
                s.append(f'<rect x="{bar_x}" y="{by + 4}" width="{bl}" height="16" rx="3" fill="{color}"/>')
            # 한국어 단위는 붙여 쓰고 영문 단위는 띄어 쓴다.
            sep = "" if unit in ("개",) else (" " if unit else "")
            s.append(txt(bar_x + bar_max + 8, by + 16,
                         fmt.format(v) + sep + unit, 10.5, "#333", anchor="start"))
    s.extend(multiline(w / 2, h - 42, wrapcap(T["r_cap"], 158), 10, "#555", 15))
    s.append("</svg>")
    return "\n".join(s)


def wrapcap(text, limit=150):
    words = text.split()
    lines, cur = [], ""
    for w in words:
        if cur and dwidth(cur) + 1 + dwidth(w) > limit:
            lines.append(cur); cur = w
        else:
            cur = w if not cur else cur + " " + w
    if cur:
        lines.append(cur)
    return "\n".join(lines)


if __name__ == "__main__":
    kind = sys.argv[1] if len(sys.argv) > 1 else "surface"
    lang = sys.argv[2] if len(sys.argv) > 2 else "ko"
    T = TEXT[lang]
    if kind == "surface":
        print(surface(T))
    elif kind == "compare":
        print(compare(T))
    elif kind == "result":
        print(result(T))
    else:
        raise SystemExit(f"unknown kind: {kind}")
