#!/usr/bin/env python3
"""agent-router-study 발행용 SVG 생성. 두 언어판을 같은 코드에서 낸다.

사용: python3 harness/chart.py <kind> <lang> > figures/<kind>-<lang>.svg
  kind: arch        MCP 요청이 Envoy를 두 번 지나는 경로
        list-empty  인자 조건 CEL을 걸면 tools/list가 비는 이유
        path-cost   오버헤드가 어느 구간에서 생기는가
        scale       복제본과 트래픽 정책 2x2
        rejection   거부가 어떤 모양으로 오는가 (블로그 전용)
  lang: ko | en

a2a-study/harness/chart.py와 같은 구조다(텍스트 카탈로그 + 함수 하나당 그림 하나 +
표준 출력). 수치는 RESULTS.md에서 옮긴 고정값이라 runs를 읽지 않는다.
"""
import sys
import unicodedata

TEXT = {
 "ko": {
  "v_title": "Agent Router를 앞에 두면 무엇이 좋아지고 어떤 비용이 드는가",
  "v_sub": "이 글이 v1.1.0에서 측정한 범위다. 로고는 Agent Router 저장소의 것(Apache 2.0).",
  "v_client": "에이전트\n(MCP 클라이언트)",
  "v_proxy": "MCP 프록시는 Envoy 파드 안 사이드카로 돈다",
  "v_srv_a": "MCP 서버 A\n도구 8종", "v_srv_b": "MCP 서버 B\n도구 2종",
  "v_gain_h": "얻는 것 (서버를 고치지 않고)",
  "v_gains": ["도구 이름만이 아니라 호출 인자 값까지 보고 허용을 정한다",
              "백엔드 여러 개를 한 주소로 묶는다",
              "도구 이름에 백엔드 이름이 붙어 어느 서버 것인지 보인다"],
  "v_cost_h": "잃는 것 (기본 설정)",
  "v_costs": ["응답이 20ms 늘고 처리량은 초당 100건 근처가 경계다",
              "프록시가 2코어 노드의 1.87코어를 쓴다",
              "원인은 세션 ID 복호화다. 반복을 1,000으로 낮추면 0.5ms가 된다"],
  "v_caveat": "단서: 인자 조건을 문서 예시 그대로 적으면 tools/list가 비어 에이전트가 도구를 찾지 못한다. CEL을 !has()로 감싸면 목록이 남고 조건도 그대로 강제된다.",
  "a_title": "MCP 요청은 Envoy를 두 번 지난다",
  "a_sub": "v1.1.0 기준이다. MCP 프록시는 Envoy 파드의 extproc 사이드카 안에서 도는 Go HTTP 서버이고 포트는 코드에 박혀 있다.",
  "a_client": "에이전트", "a_client_n": "MCP 클라이언트",
  "a_pod": "Envoy 프록시 파드",
  "a_envoy1": "Envoy", "a_envoy1_n": "수신 리스너",
  "a_proxy": "MCP 프록시", "a_proxy_n": "사이드카 안의 Go 서버\nai-gateway-extproc\n세션, 병합, 인가",
  "a_envoy2": "Envoy", "a_envoy2_n": "MCP 리스너",
  "a_backend": "MCP 서버", "a_backend_n": "백엔드 여러 개",
  "a_uds": "로컬 포트 9856", "a_local": "로컬 포트 10088",
  "a_cap": "설계 제안이 이유를 적는다."
           " Envoy 확장 메커니즘은 필터에서 스트리밍 응답을 만들지도, 임의 업스트림으로 스트리밍 호출을 하지도 못한다."
           " 클라이언트 SSE를 끊는 것과 여러 서버의 알림을 합치는 것을 필터로는 할 수 없었던 이유다."
           " 그래서 Go 서버로 두되 주고받는 트래픽은 모두 Envoy가 전달하도록 했다.",

  "l_title": "인자 값을 조건으로 걸면 목록이 비는 이유",
  "l_sub": "목록을 거를 때 프록시는 도구마다 호출을 가정하고 묻는다.",
  "l_req": "클라이언트", "l_req_n": "tools/list\nparams: {}",
  "l_ask": "도구마다 묻는다",
  "l_ask_n": 'method = "tools/call"\nparams = 목록 요청의 params',
  "l_cel": "CEL 평가",
  "l_cel_n": "request.mcp.params\n  .arguments.a == 1",
  "l_err": "no such key: arguments",
  "l_skip": "규칙을 건너뛴다",
  "l_skip_n": "CEL 오류면 continue",
  "l_deny": "defaultAction",
  "l_deny_n": "기본값 Deny",
  "l_out": "목록 0개",
  "l_out_n": "백엔드의 도구 8개가\n모두 사라진다",
  "l_fix": "되돌리는 방법",
  "l_fix_n": "!has(request.mcp.params.arguments) ||\n를 앞에 붙이면 목록 시점에는 왼쪽만 평가하고 끝난다",
  "l_cap": "호출은 되는데 목록에 없다. 에이전트는 tools/list를 보고 무엇을 호출할지 정하므로"
           " 도구가 있는 줄 모르면 통과할 호출도 하지 않는다.",

  "p_title": "통과 비용의 99%가 MCP 프록시 구간에서 생긴다",
  "p_sub": "같은 Envoy를 지나되 MCP 프록시만 건너뛴 경로를 대조군으로 두었다.",
  "p_rows": [
      ("백엔드 직접", "806 rps", "0.91ms", 0.91, "#4a7c59"),
      ("같은 Envoy, MCP 프록시 없음", "755 rps", "1.06ms", 1.06, "#4a7c59"),
      ("MCP 프록시 경유 (기본값)", "50 rps", "19.5ms", 19.5, "#b5651d"),
      ("같은 경로, 반복 횟수만 1,000", "596 rps", "1.55ms", 1.55, "#4a7c59"),
  ],
  "p_hdr": ("경로", "동시 1 처리량", "지연 p50"),
  "p_leg": "기본값에서 구간을 나눠 보면",
  "p_leg_in": "클라이언트 → MCP 프록시", "p_leg_in_v": "22ms",
  "p_leg_out": "MCP 프록시 → 백엔드", "p_leg_out_v": "1ms",
  "p_leg_first": "첫 바이트가 나가기까지 0ms",
  "p_cap": "정책이 없든 인자 값 조건 CEL이든 규칙이 20개든 같다. 규칙을 검사하는 비용이 아니다."
           " 이 구간은 프록시가 요청마다 세션 ID를 푸는 계산이다. 반복 횟수를 낮추면 프록시 몫이 20ms에서 0.5ms로 줄어든다."
           " 위 3줄은 캠페인 회차이고 마지막 줄은 반복 횟수를 확인한 별도 회차다.",

  "s_title": "복제본만 늘리면 처리량이 오르지 않는다",
  "s_sub": "목표 초당 100건을 연결마다 새로 열어 건 회차다. 기본값은 복제본 1개에 Local이다.",
  "s_cols": ("externalTrafficPolicy: Local", "externalTrafficPolicy: Cluster"),
  "s_rows": ("복제본 1", "복제본 2"),
  "s_cells": [
      [("100.0 달성", "p50 99ms", "보내지 못한 요청 0", "#b5651d", "기본값"),
       ("99.2 달성", "p50 133ms", "보내지 못한 요청 24", "#b5651d", "")],
      [("99.3 달성", "p50 118ms", "보내지 못한 요청 21", "#b5651d", "늘려도 한쪽만 받는다"),
       ("100.0 달성", "p50 25.7ms", "보내지 못한 요청 0", "#4a7c59", "")],
  ],
  "s_why": "MetalLB가 L2로 주소를 알리는 환경에서 Local이면 알림 노드의 파드만 요청을 받는다.",
  "s_cap": "둘을 같이 바꾼 조합에서만 지연이 내려간다. 복제본만 늘리거나 트래픽 정책만 바꾸면 오히려 오른다."
           " 제안 문서에 적힌 \"어떤 인스턴스도 세션을 처리할 수 있다\"가 성립한다.",

  "r_title": "거부는 HTTP 403 평문으로 돌아온다",
  "r_sub": "이 응답을 읽는 쪽은 사람이 아닌 에이전트 루프다.",
  "r_left": "Agent Router", "r_right": "agentgateway",
  "r_rows": [
      ("인가 거부", "HTTP 403\naccess denied (평문 13바이트)", "JSON-RPC 200\n\"Unknown tool\" (도구를 숨긴다)"),
      ("클라이언트가 보는 것", "전송 계층 오류", "정상 응답 안의 오류"),
      ("루프가 할 수 있는 것", "예외로 올라간다", "읽고 다음 수를 정한다"),
  ],
  "r_cap": "같은 상황에서 두 게이트웨이가 서로 다른 형태로 응답한다. 에이전트 SDK가 이 둘을"
           " 다르게 다루므로 도입 전에 오류 처리를 확인한다.",
 },
 "en": {
  "v_title": "What Agent Router adds in front of MCP servers, and what it costs",
  "v_sub": "The scope this post measured on v1.1.0. Logo from the Agent Router repository (Apache 2.0).",
  "v_client": "Agent\n(MCP client)",
  "v_proxy": "The MCP proxy runs as a sidecar inside the Envoy pod",
  "v_srv_a": "MCP server A\n8 tools", "v_srv_b": "MCP server B\n2 tools",
  "v_gain_h": "What you get, without touching the servers",
  "v_gains": ["Allow or deny on the values passed, not just the tool name",
              "Several backends behind one address",
              "The backend name is prefixed onto each tool, so its origin shows"],
  "v_cost_h": "What you pay, at the defaults",
  "v_costs": ["Responses take 20ms longer and throughput edges out near 100 per second",
              "The proxy uses 1.87 of a 2-CPU node",
              "The cause is session ID decryption. At 1,000 iterations it is 0.5ms"],
  "v_caveat": "Caveat: write the argument condition the way the documentation shows and tools/list comes back empty, so an agent finds no tools. Wrap the CEL in !has() and the list survives with the condition still enforced.",
  "a_title": "An MCP request passes through Envoy twice",
  "a_sub": "On v1.1.0. The MCP proxy is a Go HTTP server inside the extproc sidecar of the Envoy pod, and the ports are fixed in the code.",
  "a_client": "Agent", "a_client_n": "MCP client",
  "a_pod": "Envoy proxy pod",
  "a_envoy1": "Envoy", "a_envoy1_n": "inbound listener",
  "a_proxy": "MCP proxy", "a_proxy_n": "Go server in the sidecar\nai-gateway-extproc\nsessions, merge, authz",
  "a_envoy2": "Envoy", "a_envoy2_n": "MCP listener",
  "a_backend": "MCP server", "a_backend_n": "several backends",
  "a_uds": "local port 9856", "a_local": "local port 10088",
  "a_cap": "The design proposal gives the reason. Envoy's extension mechanisms cannot reply with"
           " streaming responses from a filter, nor make streaming callouts to arbitrary upstreams,"
           " so terminating client SSE and merging notifications from several servers could not be done"
           " in a filter. Hence a Go server, with Envoy still"
           " carrying every byte in and out.",

  "l_title": "Why an argument condition empties the tool list",
  "l_sub": "When filtering the list, the proxy asks about each tool as if it were being called.",
  "l_req": "Client", "l_req_n": "tools/list\nparams: {}",
  "l_ask": "asks per tool",
  "l_ask_n": 'method = "tools/call"\nparams = from tools/list',
  "l_cel": "CEL evaluation",
  "l_cel_n": "request.mcp.params\n  .arguments.a == 1",
  "l_err": "no such key: arguments",
  "l_skip": "rule is skipped",
  "l_skip_n": "CEL error means continue",
  "l_deny": "defaultAction",
  "l_deny_n": "Deny by default",
  "l_out": "0 tools listed",
  "l_out_n": "all 8 tools on the backend\nare gone",
  "l_fix": "How to get them back",
  "l_fix_n": "prefix with !has(request.mcp.params.arguments) ||\nand at list time only the left side is evaluated",
  "l_cap": "The call works but the tool is not listed. An agent reads tools/list to decide what to"
           " call, so a tool it cannot see is a call it never makes.",

  "p_title": "99% of the passthrough cost comes from the MCP proxy",
  "p_sub": "A route through the same Envoy that skips only the MCP proxy serves as the control.",
  "p_rows": [
      ("Backend directly", "806 rps", "0.91ms", 0.91, "#4a7c59"),
      ("Same Envoy, no MCP proxy", "755 rps", "1.06ms", 1.06, "#4a7c59"),
      ("Through the MCP proxy (default)", "50 rps", "19.5ms", 19.5, "#b5651d"),
      ("Same path, iteration count at 1,000", "596 rps", "1.55ms", 1.55, "#4a7c59"),
  ],
  "p_hdr": ("Path", "Throughput at 1", "Latency p50"),
  "p_leg": "Split by leg, at the default",
  "p_leg_in": "client → MCP proxy", "p_leg_in_v": "22ms",
  "p_leg_out": "MCP proxy → backend", "p_leg_out_v": "1ms",
  "p_leg_first": "0ms to first byte out",
  "p_cap": "No policy, a CEL on the values passed, or twenty rules all give the same figure."
           " It is not the cost of evaluating rules. This leg is the key derivation the proxy runs to"
           " unwrap the session ID on every request. Lowering the count drops what the proxy adds from 20ms to 0.5ms."
           " The first three rows are from the campaign; the last is a separate run that varied the count.",

  "s_title": "More replicas alone do not raise throughput",
  "s_sub": "Measured at a target of 100 requests per second. The default is one replica with Local.",
  "s_cols": ("externalTrafficPolicy: Local", "externalTrafficPolicy: Cluster"),
  "s_rows": ("1 replica", "2 replicas"),
  "s_cells": [
      [("100.0 achieved", "p50 99ms", "0 not sent", "#b5651d", "default"),
       ("99.2 achieved", "p50 133ms", "24 not sent", "#b5651d", "")],
      [("99.3 achieved", "p50 118ms", "21 not sent", "#b5651d", "only one pod works"),
       ("100.0 achieved", "p50 25.7ms", "0 not sent", "#4a7c59", "")],
  ],
  "s_why": "With MetalLB announcing the address over L2, Local sends every request to pods on the announcing node.",
  "s_cap": "Switch to Cluster and run two replicas and the target is met with latency back at its"
           " unloaded level. The proposal's claim that any instance can serve any session holds.",

  "r_title": "A denial comes back as plain HTTP 403",
  "r_sub": "An agent loop reads this response, not a person.",
  "r_left": "Agent Router", "r_right": "agentgateway",
  "r_rows": [
      ("Authorization denial", "HTTP 403\naccess denied (13 bytes, plain)", "JSON-RPC 200\n\"Unknown tool\" (tool hidden)"),
      ("What the client sees", "a transport-level error", "an error inside a normal response"),
      ("What the loop can do", "it surfaces as an exception", "read it and pick a next move"),
  ],
  "r_cap": "The two gateways take different shapes in the same situation. Agent SDKs treat them"
           " differently, so check error handling before adopting either.",
 },
}

W, H = 900, 470


def esc(t):
    return t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def dwidth(s):
    """표시 너비. 한글은 두 칸을 차지하므로 글자 수로 감싸면 어긋난다."""
    return sum(2 if unicodedata.east_asian_width(c) in ("W", "F") else 1 for c in s)


def txt(x, y, s, size=12, fill="#222", anchor="middle", bold=False, mono=False):
    f = ' font-weight="bold"' if bold else ""
    m = ' font-family="Menlo, monospace"' if mono else ""
    return (f'<text x="{x}" y="{y}" font-size="{size}" fill="{fill}" '
            f'text-anchor="{anchor}"{f}{m}>{esc(s)}</text>')


def multiline(x, y, s, size=10, fill="#666", step=14, anchor="middle", mono=False):
    return [txt(x, y + i * step, line, size, fill, anchor, mono=mono)
            for i, line in enumerate(s.split("\n"))]


def box(x, y, w, h, fill="#fafafa", stroke="#999", dash="", rx=6, sw=1.5):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" '
            f'stroke="{stroke}" stroke-width="{sw}"{d}/>')


def line_label(x, y, text, size=8.5, fill="#777"):
    w = dwidth(text) * size * 0.55 + 8
    return [f'<rect x="{x - w / 2}" y="{y - size - 1}" width="{w}" height="{size + 5}" fill="white"/>',
            txt(x, y, text, size, fill)]


def arrow(x1, y1, x2, y2, color="#555", sw=1.8, dash=""):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    return (f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" '
            f'stroke-width="{sw}" marker-end="url(#a)"{d}/>')


def wrapcap(text, limit=150):
    """캡션을 줄로 나눈다. 문장 경계를 먼저 쓰고 한 문장이 한 줄에 안 들어갈 때만
    그 문장 안에서 단어 단위로 접는다. 마침표 뒤에서 끊는 것이 가장 읽기 좋다."""
    import re
    sents = [x.strip() for x in re.split(r'(?<=[.!?])\s+', text.strip()) if x.strip()]
    lines = []
    for sent in sents:
        if dwidth(sent) <= limit:
            lines.append(sent)
            continue
        cur = ""
        for w in sent.split():
            if cur and dwidth(cur) + 1 + dwidth(w) > limit:
                lines.append(cur); cur = w
            else:
                cur = w if not cur else cur + " " + w
        if cur:
            lines.append(cur)
    return "\n".join(lines)


def vcenter(cy, s, step=14):
    """여러 줄 글의 첫 줄 y 좌표. 줄 수와 무관하게 상자 가운데에 놓인다."""
    n = len(s.split("\n"))
    return cy - (n - 1) * step / 2 + step * 0.32


def logo(path, x, y, w, vb):
    """저장소에 받아 둔 로고 SVG의 내용만 떼어 그 자리에 넣는다.
    vb 는 원본 viewBox 의 (너비, 높이)이고 그 비율로 높이를 맞춘다.
    파일이 없으면 빈 문자열을 돌려주고 호출부가 글자로 대신한다."""
    import os, re
    fp = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "figures", path)
    if not os.path.exists(fp):
        return ""
    m = re.search(r"<svg[^>]*>(.*)</svg>", open(fp).read(), re.S)
    if not m:
        return ""
    inner = re.sub(r'<rect[^>]*fill="(white|#fff|#ffffff)"[^>]*/>', "", m.group(1), count=1)
    vw, vh = vb
    h = w * vh / vw
    return (f'<svg x="{x}" y="{y}" width="{w}" height="{h:.1f}" '
            f'viewBox="0 0 {vw} {vh}">{inner}</svg>')


BOTTOM_PAD = 22


def fit(svg):
    """그려 놓은 SVG 의 높이를 내용에 맞춘다. 그림마다 아래 여백이 제각각이던 것을
    한 값(BOTTOM_PAD)으로 통일한다. 텍스트는 baseline 기준이라 한 줄 높이를 더한다."""
    import re
    ys = [float(x) for x in re.findall(r'<text[^>]*\by="([0-9.]+)"', svg)]
    rects = [(float(a), float(b)) for a, b in
             re.findall(r'<rect[^>]*\by="([0-9.-]+)"[^>]*\bheight="([0-9.]+)"', svg)]
    svgs = [(float(a), float(b)) for a, b in
            re.findall(r'<svg [^>]*\by="([0-9.-]+)"[^>]*\bheight="([0-9.]+)"', svg)]
    bottom = max([y + 4 for y in ys] + [y + h for y, h in rects + svgs] + [0])
    new_h = round(bottom + BOTTOM_PAD)
    svg = re.sub(r'(viewBox="0 0 [0-9.]+ )[0-9.]+(")', rf'\g<1>{new_h}\g<2>', svg, count=1)
    svg = re.sub(r'(<svg[^>]*?\bheight=")[0-9.]+(")', rf'\g<1>{new_h}\g<2>', svg, count=1)
    # 바탕 사각형도 같이 늘린다(첫 번째 흰 배경).
    svg = re.sub(r'(<rect width="900" height=")[0-9.]+(" fill="white"/>)',
                 rf'\g<1>{new_h}\g<2>', svg, count=1)
    return svg


def head(h=H):
    return [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {h}" '
            f'width="{W}" height="{h}" font-family="-apple-system, BlinkMacSystemFont, '
            f'\'Segoe UI\', sans-serif">',
            '<defs><marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" '
            'markerHeight="6" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="#555"/></marker>'
            '<marker id="ar" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" '
            'markerHeight="6" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="#b5651d"/></marker>'
            '</defs>',
            f'<rect width="{W}" height="{h}" fill="white"/>']


def titled(T, tk, sk, h=H):
    s = head(h)
    s.append(txt(W / 2, 32, T[tk], 17, "#111", bold=True))
    s.append(txt(W / 2, 54, T[sk], 11.5, "#777"))
    return s


def value(T):
    """도입 효과 그림: 경로 안의 Agent Router, 얻는 것과 잃는 것, 단서 한 줄."""
    s = titled(T, "v_title", "v_sub")

    cy = 128
    s.append(box(30, cy - 30, 150, 60, "#f4f7fb", "#8aa"))
    s.extend(multiline(105, vcenter(cy, T["v_client"], 15), T["v_client"], 10.5, "#333", 15))

    gx, gy, gw, gh = 268, cy - 46, 300, 92
    s.append(box(gx, gy, gw, gh, "#fcfaf7", "#c96", rx=10))
    ar = logo("_ar-horizontal-primary.svg", gx + 62, gy + 16, 176, (1471.75, 384.0))
    if ar:
        s.append(ar)
    else:
        s.append(txt(gx + gw / 2, gy + 46, "Agent Router", 15, "#c96", bold=True))
    s.append(txt(gx + gw / 2, gy + gh - 12, T["v_proxy"], 9.5, "#666"))

    for i, k in enumerate(("v_srv_a", "v_srv_b")):
        by = cy - 44 + i * 50
        s.append(box(712, by, 158, 42, "#eef7ee", "#7a9"))
        s.extend(multiline(791, vcenter(by + 21, T[k], 13), T[k], 10, "#333", 13))
    s.append(arrow(182, cy, gx - 4, cy, "#8aa"))
    s.append(arrow(gx + gw + 4, cy - 8, 710, cy - 23, "#c96"))
    s.append(arrow(gx + gw + 4, cy + 8, 710, cy + 27, "#c96"))

    ty = 212
    for x, hk, lk, fill, stroke, col in ((30, "v_gain_h", "v_gains", "#f2f7f2", "#7a9", "#2c6e49"),
                                         (460, "v_cost_h", "v_costs", "#fdf3e7", "#c96", "#b5651d")):
        s.append(box(x, ty, 410, 128, fill, stroke, rx=8))
        s.append(txt(x + 205, ty + 24, T[hk], 12, col, bold=True))
        yy = ty + 48
        for item in T[lk]:
            lines = wrapcap(item, 72).split("\n")
            s.append(txt(x + 18, yy, "\u2022", 10, col, anchor="start"))
            for j, ln in enumerate(lines):
                s.append(txt(x + 34, yy + j * 13, ln, 9.5, "#444", anchor="start"))
            yy += 13 * len(lines) + 9

    s.extend(multiline(W / 2, ty + 160, wrapcap(T["v_caveat"], 112), 9.5, "#777", 13.5))
    return fit("\n".join(s) + "\n</svg>")


def arch(T):
    """요청 경로. 로고는 theagentrouter/agent-router 의 site/static/img/brand
    (Apache 2.0)에서 받아 figures/_*.svg 로 두었다."""
    H2 = 390
    s = head(H2)
    s.append(txt(W / 2, 30, T["a_title"], 16.5, "#111", bold=True))
    s.append(txt(W / 2, 50, T["a_sub"], 11, "#777"))

    y, bh, bw = 96, 92, 128
    # 파드 경계를 먼저 깔고 그 위에 상자를 올린다.
    s.append(box(214, y - 22, 524, bh + 62, "#fcfaf7", "#c96", dash="5 4", rx=10, sw=1.3))
    ar = logo("_ar-horizontal-primary.svg", 228, y - 14, 132, (1471.75, 384.0))
    if ar:
        s.append(ar)
    else:
        s.append(txt(294, y + 2, "Agent Router", 11, "#c96", anchor="start", bold=True))
    s.append(txt(730, y + 1, T["a_pod"], 10, "#c96", anchor="end"))

    cols = [(24, "a_client", "a_client_n", "#f4f7fb", "#8aa", None),
            (228, "a_envoy1", "a_envoy1_n", "#eef3ee", "#7a9", "envoy"),
            (400, "a_proxy", "a_proxy_n", "#fdf3e7", "#c96", None),
            (572, "a_envoy2", "a_envoy2_n", "#eef3ee", "#7a9", "envoy"),
            (748, "a_backend", "a_backend_n", "#f4f7fb", "#8aa", None)]
    for x, tk, nk, fill, stroke, mark in cols:
        s.append(box(x, y + 26, bw, bh, fill, stroke))
        ty = y + 54
        if mark == "envoy":
            ev = logo("_envoy-icon-color.svg", x + bw / 2 - 13, y + 36, 26, (439.92, 332.67))
            if ev:
                s.append(ev)
                ty = y + 82
        s.append(txt(x + bw / 2, ty, T[tk], 12.5, "#222", bold=True))
        s.extend(multiline(x + bw / 2, ty + 17, T[nk], 9, "#777", 11.5))

    labels = ["", T["a_uds"], T["a_local"], ""]
    for i in range(4):
        x1 = cols[i][0] + bw + 3
        x2 = cols[i + 1][0] - 3
        s.append(arrow(x1, y + 26 + bh / 2, x2, y + 26 + bh / 2))
        if labels[i]:
            s.extend(line_label((x1 + x2) / 2, y + 26 + bh / 2 - 9, labels[i], 8.5))

    s.extend(multiline(W / 2, y + bh + 84, wrapcap(T["a_cap"], 118), 9.5, "#777", 13.5))
    return fit("\n".join(s) + "\n</svg>")


def list_empty(T):
    s = titled(T, "l_title", "l_sub", 382)
    bw, bh, y = 132, 70, 96
    steps = [("l_req", "l_req_n", "#f4f7fb", "#8aa"),
             ("l_ask", "l_ask_n", "#ffffff", "#bbb"),
             ("l_cel", "l_cel_n", "#ffffff", "#bbb"),
             ("l_skip", "l_skip_n", "#fdf3e7", "#c96"),
             ("l_deny", "l_deny_n", "#fdf3e7", "#c96"),
             ("l_out", "l_out_n", "#fbecec", "#c66")]
    xs = [16, 164, 312, 460, 608, 752]
    for i, (tk, nk, fill, stroke) in enumerate(steps):
        w = bw if i < 5 else 132
        s.append(box(xs[i], y, w, bh, fill, stroke))
        s.append(txt(xs[i] + w / 2, y + 22, T[tk], 11, "#222", bold=True))
        body = T[nk]
        s.extend(multiline(xs[i] + w / 2, vcenter(y + 46, body, 10.5), body, 8, "#777",
                           10.5, mono=(tk in ("l_req", "l_cel", "l_ask"))))
        if i:
            s.append(arrow(xs[i] - 14, y + bh / 2, xs[i] - 3, y + bh / 2))
    # CEL 오류가 규칙을 건너뛰게 만든다
    ecx = 312 + bw / 2
    # 화살표 시작점을 고정값으로 두면 글자 길이가 바뀔 때 라벨에 붙는다. 폭에서 잡는다.
    ehw = len(T["l_err"]) * 9.5 * 0.52 / 2
    s.append(txt(ecx, y + bh + 24, T["l_err"], 9.5, "#c33", mono=True))
    s.append(arrow(ecx + ehw + 16, y + bh + 20, 460 + bw / 2, y + bh + 20, "#c33", 1.4))
    # 되돌리는 방법
    fy = 208
    s.append(box(16, fy, 868, 84, "#f2f7f2", "#7a9", rx=8))
    s.append(txt(450, fy + 26, T["l_fix"], 12.5, "#2c5", bold=True))
    s.extend(multiline(450, fy + 48, T["l_fix_n"], 9.5, "#567", 13, mono=True))
    s.extend(multiline(W / 2, 336, wrapcap(T["l_cap"], 118), 9.5, "#777", 13.5))
    return fit("\n".join(s) + "\n</svg>")


def path_cost(T):
    s = titled(T, "p_title", "p_sub", 396)
    y0, rh = 96, 52
    hdr = T["p_hdr"]
    s.append(txt(46, y0 - 8, hdr[0], 10, "#999", anchor="start"))
    s.append(txt(470, y0 - 8, hdr[1], 10, "#999"))
    s.append(txt(570, y0 - 8, hdr[2], 10, "#999"))
    maxv = max(r[3] for r in T["p_rows"])
    for i, (name, rps, lat, v, color) in enumerate(T["p_rows"]):
        y = y0 + i * rh
        s.append(txt(46, y + 20, name, 11.5, "#333", anchor="start"))
        s.append(txt(470, y + 20, rps, 11, "#555"))
        s.append(txt(570, y + 20, lat, 11.5, color, bold=True))
        bw = max(4, 206 * v / maxv)
        s.append(f'<rect x="630" y="{y + 9}" width="{bw}" height="14" rx="3" fill="{color}" opacity="0.75"/>')
    # 구간 분해
    ly = y0 + len(T["p_rows"]) * rh + 22
    s.append(txt(46, ly, T["p_leg"], 11, "#999", anchor="start"))
    s.append(box(46, ly + 10, 380, 40, "#fdf3e7", "#c96"))
    s.append(txt(236, ly + 28, T["p_leg_in"], 10.5, "#555"))
    s.append(txt(236, ly + 43, T["p_leg_in_v"], 13, "#b5651d", bold=True))
    s.append(box(456, ly + 10, 380, 40, "#eef3ee", "#8a8"))
    s.append(txt(646, ly + 28, T["p_leg_out"], 10.5, "#555"))
    s.append(txt(646, ly + 43, T["p_leg_out_v"], 13, "#4a7c59", bold=True))
    s.append(txt(W / 2, ly + 70, T["p_leg_first"], 10, "#999"))
    s.extend(multiline(W / 2, ly + 96, wrapcap(T["p_cap"], 118), 9.5, "#777", 13.5))
    return fit("\n".join(s) + "\n</svg>")


def scale(T):
    s = titled(T, "s_title", "s_sub", 414)
    x0, y0, cw, ch = 160, 106, 320, 96
    for j, c in enumerate(T["s_cols"]):
        s.append(txt(x0 + j * (cw + 20) + cw / 2, y0 - 10, c, 11, "#666", mono=True))
    for i, r in enumerate(T["s_rows"]):
        s.append(txt(x0 - 16, y0 + i * (ch + 18) + ch / 2, r, 12, "#444", anchor="end", bold=True))
        for j in range(2):
            got, p50, shed, color, note = T["s_cells"][i][j]
            x = x0 + j * (cw + 20)
            y = y0 + i * (ch + 18)
            s.append(box(x, y, cw, ch, "#ffffff", color, sw=2))
            s.append(txt(x + cw / 2, y + 28, got, 13.5, color, bold=True))
            s.append(txt(x + cw / 2, y + 48, p50, 11.5, "#555"))
            s.append(txt(x + cw / 2, y + 66, shed, 10.5, "#777"))
            if note:
                s.append(txt(x + cw / 2, y + 85, note, 9.5, "#999"))
    s.append(txt(W / 2, y0 + 2 * (ch + 18) + 16, T["s_why"], 10, "#888"))
    s.extend(multiline(W / 2, y0 + 2 * (ch + 18) + 44, wrapcap(T["s_cap"], 118), 9.5, "#777", 14))
    return fit("\n".join(s) + "\n</svg>")


def rejection(T):
    """두 게이트웨이의 거부 형태 비교. 로고는 각 프로젝트 저장소에서 받았다
    (Agent Router: Apache 2.0, agentgateway: Apache 2.0)."""
    H2 = 372
    s = head(H2)
    s.append(txt(W / 2, 30, T["r_title"], 16.5, "#111", bold=True))
    s.append(txt(W / 2, 50, T["r_sub"], 11, "#777"))

    lx, rx, cw, y0, rh = 222, 528, 268, 108, 72
    ar = logo("_ar-horizontal-primary.svg", lx + cw / 2 - 66, y0 - 46, 132, (1471.75, 384.0))
    if ar:
        s.append(ar)
    else:
        s.append(txt(lx + cw / 2, y0 - 14, T["r_left"], 12.5, "#b5651d", bold=True))
    ag = logo("_agentgateway-logo.svg", rx + cw / 2 - 72, y0 - 46, 144, (4496, 1064))
    if ag:
        s.append(ag)
    else:
        s.append(txt(rx + cw / 2, y0 - 14, T["r_right"], 12.5, "#4a7c59", bold=True))

    bh = rh - 12
    for i, (label, left, right) in enumerate(T["r_rows"]):
        y = y0 + i * rh
        cy = y + bh / 2
        s.append(txt(lx - 16, cy + 4, label, 11, "#555", anchor="end"))
        s.append(box(lx, y, cw, bh, "#fdf3e7", "#c96"))
        s.extend(multiline(lx + cw / 2, vcenter(cy, left), left, 10, "#555", 14))
        s.append(box(rx, y, cw, bh, "#eef3ee", "#7a9"))
        s.extend(multiline(rx + cw / 2, vcenter(cy, right), right, 10, "#555", 14))

    s.extend(multiline(W / 2, y0 + 3 * rh + 24, wrapcap(T["r_cap"], 118), 9.5, "#777", 13.5))
    return fit("\n".join(s) + "\n</svg>")


KINDS = {"value": value, "arch": arch, "list-empty": list_empty, "path-cost": path_cost,
         "scale": scale, "rejection": rejection}

if __name__ == "__main__":
    kind = sys.argv[1] if len(sys.argv) > 1 else "arch"
    lang = sys.argv[2] if len(sys.argv) > 2 else "ko"
    if kind not in KINDS:
        raise SystemExit(f"unknown kind: {kind}")
    print(KINDS[kind](TEXT[lang]))
