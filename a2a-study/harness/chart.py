#!/usr/bin/env python3
"""a2a-study 발행용 SVG 생성. 두 언어판을 같은 코드에서 낸다.

사용: python3 harness/chart.py <kind> <lang> > figures/<kind>-<lang>.svg
  kind: surface   Q1의 "보이는 것은 4가지뿐" 도식
        compare   Q4의 "MCP와 A2A는 상대가 다르다" 비교표
        result    결과 절의 "얻는 것과 잃는 것" 한눈 비교
        version   헤더 하나가 두 세대를 나누는 것 (블로그 전용)
        waiting   15초 동안의 왕복 비교 (블로그 전용)
  lang: ko | en

version 과 waiting 은 README 에 쓰지 않는다. 블로그가 README 보다 친절해야 해서
표와 문장으로만 있던 두 대목을 그림으로 더 그린 것이다.

agentgateway-study/harness/chart.py와 같은 구조다(텍스트 카탈로그 + 함수 하나당
그림 하나 + 표준 출력). 수치 그림이 아니라 개념 도식이므로 runs를 읽지 않는다.
"""
import sys
import unicodedata

TEXT = {
    "ko": {
        "title": "상대는 불투명하고 보이는 것은 4가지뿐이다",
        "sub": "A2A가 정한 것은 이 4가지와 이들을 나르는 전송 규칙이다.",
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
        "a_peer": "일을 대신 한다",
        "cap": "이 연구가 확인하는 것은 이 4가지가 스펙대로 동작하는가이다. 카드의 선언이 실제로 강제되는가(선언 대 실제),"
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
        "c_e1": "도구를 직접 쓴다", "c_e2": "남에게 일을 넘긴다",
        "c_e3": "자기 도구는 MCP로",
        "c_cap": "둘은 순서가 아니라 선택이다. 도구를 직접 쓰면 MCP만 있으면 되고 남에게 일을 맡길 때 A2A를 쓴다."
                 " 받은 쪽이 자기 도구를 부르는 것은 그쪽 사정이고 내가 거쳐 가는 경로가 아니다.",
        "r_title": "얻는 것과 잃는 것",
        "r_sub": "같은 작업을 3가지로 만들어 비교했다. 칸마다 조건이 다르고 3개 다 낮을수록 좋다.",
        "r_p1": "상대가 바뀌면 다시 만들 항목",
        "r_p1u": "개", "r_p1n": "A2A만 스펙이 정해 준다",
        "r_p2": "응답 1건당 바이트",
        "r_p2u": "B", "r_p2n": "부하 없이 단발 호출 1회",
        "r_p3": "호출당 지연 p50",
        "r_p3u": "ms", "r_p3n": "100rps, 연결 재사용",
        "r_cap": "왼쪽이 얻는 것이고 오른쪽 둘이 잃는 것이다. 파란 막대가 왼쪽에서는 가장 짧고 오른쪽에서는 가장 길다."
                 " 바이트가 큰 것은 태스크 객체가 매번 따라오기 때문이다. 짧은 단발 호출이라면 왼쪽에서 얻을 것이 없어 비용만 남는다.",
        "v_title": "같은 주소가 헤더 하나로 두 세대로 나누어진다",
        "v_sub": "헤더를 빠뜨리면 오류가 아니라 v0.3으로 처리된다.",
        "v_client": "클라이언트 요청",
        "v_server": "서버 1대",
        "v_handled": "처리되는 세대",
        "v_c1": "헤더 없음",
        "v_c1n": "A2A-Version 헤더를 안 보냄",
        "v_c2": "A2A-Version: 0.3",
        "v_c2n": "이전 버전을 명시",
        "v_c3": "A2A-Version: 1.0",
        "v_c3n": "새 버전을 명시",
        "v_g1": "v0.3으로 처리",
        "v_g1n": "메서드 이름도 상태 이름도 v0.3",
        "v_g2": "v1.0으로 처리",
        "v_g2n": "새 이름과 새 형식",
        "v_warn": "오류 없이 조용히",
        "v_band": "REST는 경로까지 나누어지는데 이름과 실제가 반대로 보인다",
        "v_p1": "/a2a/rest/", "v_p1v": "v1.0",
        "v_p2": "/a2a/rest/v1/", "v_p2v": "v0.3",
        "v_cap": "JSON-RPC는 주소 하나에서 헤더로만 나누어진다. 스펙 3.6.1절이 헤더를 반드시 보내라고 하면서"
                 " 같은 문장에서 헤더가 없으면 v0.3으로 본다고 적어 두었다. 그래서 헤더를 빠뜨린 v1.0 클라이언트는"
                 " 정상 응답을 받으면서 v0.3으로 처리된다.",
        "w_title": "15초 걸리는 일을 맡겨 놓고 무엇을 하는가",
        "w_sub": "걸린 시간은 세 구현 모두 15.1~15.2초로 같았다. 다른 것은 그동안의 왕복이다.",
        "w_start": "맡김",
        "w_done": "결과",
        "w_r1": "HTTP와 MCP의 폴링",
        "w_r1n": "앱에 직접 만든 상태 조회. 1회 92B",
        "w_r2": "A2A의 폴링",
        "w_r2n": "태스크 객체가 전부 실려 온다. 1회 571B",
        "w_r3": "A2A의 스트리밍과 푸시",
        "w_r3n": "확인하러 가지 않는다. 서버가 보낸다",
        "w_poll": "확인",
        "w_ev": "이벤트",
        "w_push": "푸시 1회",
        "w_zero": "상태 확인 왕복 0",
        "w_cap": "폴링만 놓고 보면 A2A가 가장 비싸다. 그런데 A2A는 폴링을 하지 않아도 된다."
                 " 스트리밍과 푸시가 스펙 안에 있어서 확인하러 가는 왕복이 0이 된다."
                 " 다른 두 구현에서 같은 것을 하려면 SSE 엔드포인트와 웹훅 발송 기능을 직접 만들어야 한다."
                 " 확인 횟수는 얼마나 자주 묻느냐에 달렸고 그림에서는 5회를 예로 들었다.",
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
        "r_p1u": "", "r_p1n": "only in A2A does the spec fix them",
        "r_p2": "bytes per response",
        "r_p2u": "B", "r_p2n": "one call, no load",
        "r_p3": "latency per call, p50",
        "r_p3u": "ms", "r_p3n": "100 rps, connection reuse",
        "r_cap": "The left panel is what you get; the two on the right are what you pay. The blue bar is the shortest on the left"
                 " and the longest on the right. The bytes are high because the task object rides along every time. For short one-shot calls"
                 " there is nothing to gain on the left, so only the cost remains.",
        "v_title": "One header splits the same address into two generations",
        "v_sub": "Omit it and you get v0.3, not an error.",
        "v_client": "client request",
        "v_server": "one server",
        "v_handled": "generation used",
        "v_c1": "no header",
        "v_c1n": "A2A-Version not sent",
        "v_c2": "A2A-Version: 0.3",
        "v_c2n": "asks for the old one",
        "v_c3": "A2A-Version: 1.0",
        "v_c3n": "asks for the new one",
        "v_g1": "handled as v0.3",
        "v_g1n": "old method names, old state names",
        "v_g2": "handled as v1.0",
        "v_g2n": "new names, new shape",
        "v_warn": "no error, no sign",
        "v_band": "REST splits by path too, and the names read backwards",
        "v_p1": "/a2a/rest/", "v_p1v": "v1.0",
        "v_p2": "/a2a/rest/v1/", "v_p2v": "v0.3",
        "v_cap": "JSON-RPC splits on the header alone, at one address. Spec 3.6.1 says clients MUST send the header"
                 " and, in the same sentence, that an absent header means v0.3. So a v1.0 client that forgets it"
                 " gets normal responses while being served the older generation.",
        "w_title": "What you can do while a 15-second job runs",
        "w_sub": "All three took 15.1-15.2 s. What differs is the round trips in between.",
        "w_start": "handed off",
        "w_done": "result",
        "w_r1": "polling on HTTP and MCP",
        "w_r1n": "a status call built by hand. 92 B each",
        "w_r2": "polling on A2A",
        "w_r2n": "the whole task object rides along. 571 B each",
        "w_r3": "A2A streaming and push",
        "w_r3n": "you do not go and check. the server sends",
        "w_poll": "check",
        "w_ev": "event",
        "w_push": "one push",
        "w_zero": "zero status round trips",
        "w_cap": "On polling alone A2A is the most expensive. But A2A does not have to poll:"
                 " streaming and push are in the spec, which takes the status round trips to zero."
                 " Doing the same on the other two means building an SSE endpoint and a webhook sender yourself.",
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

    # 아래 띠: 두 갈래. 일렬로 그리면 "A2A를 거쳐야 MCP에 닿는다"로 읽힌다.
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

    # 갈래 2. 남에게 일을 넘긴다 (A2A)
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
    """결과 절의 한눈 비교. 얻는 것 하나와 잃는 것 둘을 같은 형태의 막대로 놓아
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


def version(T):
    """헤더 하나가 두 세대를 나누는 것. 블로그 전용(README에는 없다)."""
    w, h = 900, 470
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" '
         f'font-family="Helvetica, Arial, sans-serif">',
         f'<rect width="{w}" height="{h}" fill="white"/>',
         '<defs><marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" '
         'markerHeight="6" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="#555"/></marker></defs>']
    s.append(txt(w / 2, 32, T["v_title"], 15, "#111", bold=True))
    s.append(txt(w / 2, 52, T["v_sub"], 11, "#777"))

    cw, ch = 196, 52
    cx = 44
    ys = [92, 168, 244]
    s.append(txt(cx, 80, T["v_client"], 10.5, "#888", anchor="start", bold=True))
    keys = [("v_c1", "v_c1n"), ("v_c2", "v_c2n"), ("v_c3", "v_c3n")]
    for i, (kt, kn) in enumerate(keys):
        y = ys[i]
        hot = i == 0
        s.append(box(cx, y, cw, ch, fill="#fff7f2" if hot else "#fafafa",
                     stroke="#d9822b" if hot else "#999"))
        s.append(txt(cx + cw / 2, y + 22, T[kt], 11.5, "#222", bold=True, mono=(i > 0)))
        s.append(txt(cx + cw / 2, y + 38, T[kn], 9, "#888"))

    # 서버
    sx, sy, sw_, sh_ = 356, 92, 150, 204
    s.append(box(sx, sy, sw_, sh_, fill="#ffffff", stroke="#326CE5", sw=1.6))
    s.append(f'<rect x="{sx}" y="{sy}" width="{sw_}" height="26" rx="6" fill="#326CE5"/>')
    s.append(f'<rect x="{sx}" y="{sy + 16}" width="{sw_}" height="10" fill="#326CE5"/>')
    s.append(txt(sx + sw_ / 2, sy + 18, T["v_server"], 11.5, "#ffffff", bold=True))
    s.append(txt(sx + sw_ / 2, sy + 116, "/a2a/jsonrpc", 10, "#555", mono=True))
    s.append(txt(sx + sw_ / 2, sy + 134, "v0.3 + v1.0", 9.5, "#999"))

    # 처리 결과
    gx, gw, gh = 640, 216, 62
    gys = [104, 214]
    s.append(txt(gx, 80, T["v_handled"], 10.5, "#888", anchor="start", bold=True))
    for i, (kt, kn) in enumerate([("v_g1", "v_g1n"), ("v_g2", "v_g2n")]):
        y = gys[i]
        s.append(box(gx, y, gw, gh, fill="#fafafa",
                     stroke="#326CE5" if i else "#b5b5b5"))
        s.append(txt(gx + gw / 2, y + 24, T[kt], 12, "#222", bold=True))
        s.extend(multiline(gx + gw / 2, y + 42, wrapcap(T[kn], 30), 9, "#777", 11))

    # 화살표
    for i in range(3):
        y = ys[i] + ch / 2
        s.append(f'<line x1="{cx + cw + 6}" y1="{y}" x2="{sx - 8}" y2="{y}" '
                 f'stroke="{"#d9822b" if i == 0 else "#7b8ca5"}" stroke-width="1.8" '
                 f'marker-end="url(#a)"/>')
    s.append(f'<line x1="{sx + sw_ + 6}" y1="{gys[0] + gh / 2}" x2="{gx - 8}" '
             f'y2="{gys[0] + gh / 2}" stroke="#7b8ca5" stroke-width="1.8" marker-end="url(#a)"/>')
    s.append(f'<line x1="{sx + sw_ + 6}" y1="{gys[1] + gh / 2}" x2="{gx - 8}" '
             f'y2="{gys[1] + gh / 2}" stroke="#326CE5" stroke-width="1.8" marker-end="url(#a)"/>')
    s.extend(line_label((sx + sw_ + gx) / 2, gys[0] + gh / 2 - 9, T["v_warn"], 9, "#d9822b"))

    # 아래 띠: 경로 이름 역전
    by = 330
    s.append(txt(cx, by - 8, T["v_band"], 11, "#777", anchor="start", bold=True))
    s.append(box(cx, by, w - cx * 2, 66, fill="#fbfcfe", stroke="#dde3ee"))
    for i, (kp, kv) in enumerate([("v_p1", "v_p1v"), ("v_p2", "v_p2v")]):
        px = cx + 40 + i * 400
        s.append(txt(px, by + 30, T[kp], 12, "#333", anchor="start", mono=True))
        s.append(f'<line x1="{px + 130}" y1="{by + 26}" x2="{px + 186}" y2="{by + 26}" '
                 f'stroke="#7b8ca5" stroke-width="1.6" marker-end="url(#a)"/>')
        s.append(txt(px + 216, by + 30, T[kv], 12.5, "#326CE5" if i == 0 else "#777",
                     anchor="start", bold=True))
    s.extend(multiline(w / 2, 428, wrapcap(T["v_cap"], 92), 9.5, "#777", 13))
    s.append("</svg>")
    return "\n".join(s)


def waiting(T):
    """15초 동안의 왕복 비교. 블로그 전용(README에는 없다)."""
    w, h = 900, 430
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" '
         f'font-family="Helvetica, Arial, sans-serif">',
         f'<rect width="{w}" height="{h}" fill="white"/>',
         '<defs><marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" '
         'markerHeight="6" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="#555"/></marker><marker id="ab" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="#326CE5"/></marker></defs>']
    s.append(txt(w / 2, 32, T["w_title"], 15, "#111", bold=True))
    s.append(txt(w / 2, 52, T["w_sub"], 11, "#777"))

    x0, x1 = 250, 800
    rows = [110, 208, 306]
    # 시간축 눈금
    s.append(txt(x0, 84, T["w_start"], 9.5, "#888"))
    s.append(txt(x1, 84, T["w_done"], 9.5, "#888"))
    for x in (x0, x1):
        s.append(f'<line x1="{x}" y1="{90}" x2="{x}" y2="{356}" stroke="#e3e3e3" '
                 f'stroke-width="1" stroke-dasharray="3 3"/>')

    specs = [("w_r1", "w_r1n", "#7b8ca5", 5, T["w_poll"], "92B"),
             ("w_r2", "w_r2n", "#d9822b", 5, T["w_poll"], "571B"),
             ("w_r3", "w_r3n", "#326CE5", 0, "", "")]
    for i, (kt, kn, color, n, plabel, blabel) in enumerate(specs):
        y = rows[i]
        s.append(txt(30, y - 4, T[kt], 12, "#222", anchor="start", bold=True))
        s.append(txt(30, y + 13, T[kn], 9, "#888", anchor="start"))
        s.append(f'<line x1="{x0}" y1="{y}" x2="{x1}" y2="{y}" stroke="#ccc" stroke-width="2"/>')
        s.append(f'<circle cx="{x0}" cy="{y}" r="4.5" fill="#555"/>')
        s.append(f'<circle cx="{x1}" cy="{y}" r="4.5" fill="{color}"/>')
        if n:
            step = (x1 - x0) / (n + 1)
            for k in range(1, n + 1):
                px = x0 + step * k
                s.append(f'<line x1="{px}" y1="{y}" x2="{px}" y2="{y - 22}" '
                         f'stroke="{color}" stroke-width="1.4"/>')
                s.append(f'<circle cx="{px}" cy="{y - 24}" r="3.5" fill="{color}"/>')
            s.append(txt((x0 + x1) / 2, y - 34, f"{plabel}마다 {blabel}", 9.5, color))
        else:
            # 서버가 보내는 쪽. 이벤트 4개와 푸시 1회.
            for k, px in enumerate([x0 + 110, x0 + 240, x0 + 370, x1 - 20]):
                s.append(f'<line x1="{px}" y1="{y + 30}" x2="{px}" y2="{y + 5}" '
                         f'stroke="{color}" stroke-width="1.4" marker-end="url(#ab)"/>')
                s.append(f'<circle cx="{px}" cy="{y + 32}" r="3.5" fill="{color}"/>')
            s.append(txt((x0 + x1) / 2, y + 54, T["w_ev"] + " / " + T["w_push"], 9.5, color))
            s.extend(line_label((x0 + x1) / 2, y - 14, T["w_zero"], 9.5, color))

    s.extend(multiline(w / 2, 386, wrapcap(T["w_cap"], 92), 9.5, "#777", 13))
    s.append("</svg>")
    return "\n".join(s)


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
    elif kind == "version":
        print(version(T))
    elif kind == "waiting":
        print(waiting(T))
    else:
        raise SystemExit(f"unknown kind: {kind}")
