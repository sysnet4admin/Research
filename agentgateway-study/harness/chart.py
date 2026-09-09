#!/usr/bin/env python3
"""발행용 차트 2종 생성 (mcp-migration chart.py 선례).

1. cost:   경로 비용. 통제 쌍 4개(A/B close, A/B reuse, guardrail close,
           guardrail reuse)의 p50 막대와 p99 라벨. 원값 JSON에서 직접 계산.
2. reject: 거부 형태 3분류 도식 (인가 위장 / guardrail 사유 / FailClosed).

사용: python3 harness/chart.py <study_dir> <cost|reject> [en|ko] > out.svg

주의: 공개 저장소에는 측정 원자료(runs/)가 포함되지 않는다. cost 차트는
원자료가 있을 때만 재생성되고, 발행 수치는 README 표에 문서화돼 있다.
"""

import glob
import json
import os
import statistics
import sys


def med(study, rel_prefix):
    """셀 프리픽스(n1~n5)의 p50, p99 중앙값."""
    p50s, p99s = [], []
    for f in sorted(glob.glob(os.path.join(study, rel_prefix + "-n*.json"))):
        d = json.load(open(f))
        p50s.append(d["latency_ms"]["p50"])
        p99s.append(d["latency_ms"]["p99"])
    return statistics.median(p50s), statistics.median(p99s)


TEXT = {
    "ko": {
        "c_title": "무엇을 더하면 지연이 얼마나 느는가 (p50 중앙값의 차이, 각 5회)",
        "c_sub": "각 행 = 같은 날 잰 통제 쌍. 점 = 실측 p50 절대값, 오른쪽 = 뒤 값에서 앞 값을 뺀 중앙값 차이(본문 표의 증분은 짝 평균). 절대값 비교는 행 안에서만(측정일 상이). p99는 본문 표.",
        "q1": "질문 1. 게이트웨이를 거치면?", "q1sub": "직접 호출 대 게이트웨이 경유",
        "q2": "질문 2. guardrail 인자 검사를 켜면?", "q2sub": "호출마다 인자 검사 서버로 가는 gRPC 왕복이 추가된다",
        "close": "연결 매번 새로", "reuse": "연결 재사용", "arrow": "->",
        "b1": "직접", "a1": "게이트웨이 경유", "b2": "검사 없음", "a2": "검사 켬(+gRPC 왕복)",
        "take1": "홉 비용 +0.2~0.8ms. 연결을 재사용할수록 상대적으로 크게 보인다",
        "take2": "인자 검사 비용은 호출당 1ms 아래(여기 +0.1~0.5ms. README 표의 포화 400rps 행은 0.7ms)",
        "t_title": "게이트웨이를 거치면 꼬리(p99)가 어떻게 되는가: 백엔드 처리 시간별",
        "t_sub": "직접 호출과 게이트웨이 경유, 각 5회 중앙값. 100rps, 서버 쪽 echo 지연 0/10/50/200ms, 30초 셀.",
        "t_p50": "p50 증분", "t_p99": "p99 증분", "t_x": "백엔드 처리 시간(ms)",
        "t_abs": "p99 절대값: 직접 호출 대 게이트웨이 경유 (로그 눈금)", "t_direct": "직접 호출", "t_gw": "게이트웨이 경유",
        "t_row2": "게이트웨이 경유에서 직접 호출을 뺀 값 (회차별 쌍 차이의 중앙값)",
        "v_title": "게이트웨이를 사이에 두면 무엇이 좋아지고 어떤 비용이 드는가",
        "v_sub": "이 연구가 v1.5.0에서 실측한 범위. 로고는 agentgateway 프로젝트 저장소의 것(Apache 2.0).",
        "v_client": "에이전트\n(MCP 클라이언트)", "v_server": "MCP 서버", "v_agent": "A2A 에이전트",
        "v_proxy": "프록시 v1.5.0 (Rust), Kubernetes 모드",
        "v_gain_h": "얻는 것 (서버 수정 없이)",
        "v_gains": ["도구 노출 통제: 화이트리스트 + 목록 필터링", "인자 검사: guardrail gRPC 서버 경유", "트레이스 전파: 헤더와 _meta 양쪽", "A2A: 카드 주소 재작성, JSON-RPC 로그"],
        "v_cost_h": "내는 것",
        "v_costs": ["홉 p50 +0.2~0.8ms (연결 방식에 따라)", "p99는 낮아지지 않음. 재사용 + 에코급 백엔드에서만 +몇 ms", "guardrail 검사 호출당 1ms 아래"],
        "v_direct": "직접 호출 (통제 대조군)", "v_gw": "게이트웨이 경유",
        "v_caveat": "단서: 정책이 수용돼도 쓴 대로 강제되지 않을 수 있다. 인자 조건 정책은 정상 보고 뒤 백엔드 전체를 잠근다. 켠 뒤 실제 호출로 확인.",
        "a_title": "측정 구조: 무엇을 어디에 두었는가",
        "a_sub": "VirtualBox 3노드 Kubernetes v1.37.0 (M4 Pro). 부하와 프로브는 호스트에서, 두 경로의 차이는 대상 주소뿐.",
        "a_host": "호스트 (macOS)", "a_loadgen": "부하 생성기\nloadgen.py (100/200rps)", "a_probe": "결정론 프로브\nrv_run_axes.sh 등",
        "a_cluster": "aaif-benchmark 클러스터 (Kubernetes v1.37.0, Calico)",
        "a_cp": "agentgateway 컨트롤 플레인\nGateway API + CRD 감시", "a_proxy": "agentgateway 프록시 v1.5.0\nRust 데이터 플레인",
        "a_policy": "AgentgatewayPolicy\nmcpAuthorization (CEL)\nmcpGuardrails", "a_gr": "guardrail 서버\n(자작 gRPC, k8s/guardrail)",
        "a_backend": "mcp-b (MCP 서버, SDK 2.0.0)\n도구 8종, 레플리카 1", "a_tap": "탭 프록시\n(트레이스 헤더와 _meta 기록)",
        "a_direct": "직접 경로 (LoadBalancer)", "a_gw": "게이트웨이 경로 (/b)", "a_grpc": "gRPC 검사 왕복",
        "a_cap": "직접 경로와 게이트웨이 경로를 회차 안에서 교대로 재고, 정책과 guardrail은 켜고 끄며 같은 백엔드에 붙인다.",
        "t_take": "v1.4.1에서 봤던 \"게이트웨이가 꼬리를 평탄화한다\"는 재현되지 않았다. 매번 새 연결에서는 두 선이 겹치고 연결 재사용의 꼬리 손해(0ms에서 8.9 대 16.3ms)는 백엔드가 느려질수록 사라진다. p50 비용은 본문 표에서 전 구간 1ms 아래다.",
        "r_title": "요청이 거부될 때 클라이언트가 보는 세 가지 형태",
        "r_sub": "거부한 층에 따라 응답 모양이 갈린다. 모양이 곧 진단 단서다.",
        "p_client": "클라이언트", "p_gw": "게이트웨이", "p_authz": "인가 정책 (mcpAuthorization)",
        "p_gr": "guardrail 검사 서버", "p_srv": "MCP 서버", "p_grpc": "gRPC 왕복",
        "p_cap": "세 형태 모두 요청이 MCP 서버에 닿기 전에 멈춘다.",
        "r1h": "mcpAuthorization 거부", "r1b": "HTTP 400\n-32602 \"Unknown tool\"",
        "r1n": "도구 부재와 구분되지 않는 응답.\ntools/list에서도 숨겨진다",
        "r2h": "mcpGuardrails 거부", "r2b": "HTTP 200\n-32001 + 서버가 정한 사유",
        "r2n": "사유가 그대로 나간다\n(\"a == 1일 때만 허용\")",
        "r3h": "FailClosed (서버 다운)", "r3b": "HTTP 200\n-32603 내부 오류 문구",
        "r3n": "guardrail 죽으면 전부 차단.\n내부 상태가 노출된다",
    },
    "en": {
        "c_title": "What each addition costs in latency (difference of median p50, n=5 each)",
        "c_sub": "Each row = a same-day controlled pair. Dots = measured p50, right = difference of medians (tables report mean pair increments). Compare absolutes within a row only (days differ). p99 in the tables.",
        "q1": "Q1. Adding the gateway hop?", "q1sub": "direct call vs through the gateway",
        "q2": "Q2. Turning on guardrail argument checks?", "q2sub": "adds a per-call gRPC round trip to the check server",
        "close": "new conn per call", "reuse": "connection reuse", "arrow": "->",
        "b1": "direct", "a1": "via gateway", "b2": "no check", "a2": "check on (+gRPC round trip)",
        "take1": "Hop cost +0.2 to 0.8 ms; looms larger when clients reuse connections",
        "take2": "Argument checking costs under 1 ms per call (+0.1 to 0.5 ms here; 0.7 ms in the README's saturated 400 rps row)",
        "t_title": "What happens to the tail (p99) through the gateway, by backend processing time",
        "t_sub": "Direct versus through the gateway, medians of 5 runs. 100 rps, server-side echo delay 0/10/50/200 ms, 30-second cells.",
        "t_p50": "p50 increment", "t_p99": "p99 increment", "t_x": "backend processing time (ms)",
        "t_abs": "p99, absolute: direct versus through the gateway (log scale)", "t_direct": "direct", "t_gw": "through the gateway",
        "t_row2": "through the gateway minus direct (median of pair differences)",
        "v_title": "What the gateway adds when it sits in the path, and what it costs",
        "v_sub": "The scope this study measured on v1.5.0. Logo from the agentgateway project repository (Apache 2.0).",
        "v_client": "agent\n(MCP client)", "v_server": "MCP server", "v_agent": "A2A agent",
        "v_proxy": "proxy v1.5.0 (Rust), Kubernetes mode",
        "v_gain_h": "What you get (servers untouched)",
        "v_gains": ["tool exposure control: allowlist + list filtering", "argument checks: through a guardrail gRPC server", "trace propagation: header and _meta", "A2A: card address rewrite, JSON-RPC logs"],
        "v_cost_h": "What it costs",
        "v_costs": ["hop p50 +0.2 to 0.8 ms (by connection mode)", "p99 not lowered; +a few ms only with reuse against an echo-class backend", "guardrail check under 1 ms per call"],
        "v_direct": "direct call (control arm)", "v_gw": "through the gateway",
        "v_caveat": "Caveat: an accepted policy is not always enforced as written. An argument-conditioned policy reports healthy, then locks the whole backend. Verify with real calls.",
        "a_title": "Measurement setup: what sits where",
        "a_sub": "VirtualBox, 3-node Kubernetes v1.37.0 (M4 Pro). Load and probes run on the host; the two paths differ only in the target address.",
        "a_host": "host (macOS)", "a_loadgen": "load generator\nloadgen.py (100/200 rps)", "a_probe": "deterministic probes\nrv_run_axes.sh and friends",
        "a_cluster": "aaif-benchmark cluster (Kubernetes v1.37.0, Calico)",
        "a_cp": "agentgateway control plane\nwatches Gateway API + CRDs", "a_proxy": "agentgateway proxy v1.5.0\nRust data plane",
        "a_policy": "AgentgatewayPolicy\nmcpAuthorization (CEL)\nmcpGuardrails", "a_gr": "guardrail server\n(own gRPC, k8s/guardrail)",
        "a_backend": "mcp-b (MCP server, SDK 2.0.0)\n8 tools, 1 replica", "a_tap": "tap proxy\n(records trace header and _meta)",
        "a_direct": "direct path (LoadBalancer)", "a_gw": "gateway path (/b)", "a_grpc": "gRPC check round trip",
        "a_cap": "Direct and gateway paths alternate within each repetition; policies and the guardrail are toggled on the same backend.",
        "t_take": "The v1.4.1 observation that the gateway flattens the tail did not reproduce: with a new connection per call the two lines coincide, and the reuse-mode tail penalty (8.9 versus 16.3 ms at 0 ms) fades as the backend gets slower. The p50 cost, in the table above, stays under 1 ms throughout.",
        "r_title": "Three rejection shapes the client sees",
        "r_sub": "The rejecting layer decides the shape, and the shape is the diagnostic clue.",
        "p_client": "client", "p_gw": "gateway", "p_authz": "authorization policy (mcpAuthorization)",
        "p_gr": "guardrail check server", "p_srv": "MCP server", "p_grpc": "gRPC round trip",
        "p_cap": "In all three shapes the request stops before reaching the MCP server.",
        "r1h": "mcpAuthorization deny", "r1b": "HTTP 400\n-32602 \"Unknown tool\"",
        "r1n": "Indistinguishable from no-such-tool;\nhidden from tools/list",
        "r2h": "mcpGuardrails deny", "r2b": "HTTP 200\n-32001 + server reason",
        "r2n": "The reason string passes through\n(\"allowed only with a == 1\")",
        "r3h": "FailClosed (server down)", "r3b": "HTTP 200\n-32603 internal error text",
        "r3n": "Guardrail down blocks all calls;\ninternal state leaks in the message",
    },
}


def svg_head(w, h):
    return [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" '
            f'font-family="Helvetica, Arial, sans-serif">',
            f'<rect width="{w}" height="{h}" fill="white"/>']


def cost(study, T):
    ab = os.path.join("runs", "rv-ab-0902")
    wk = os.path.join("runs", "rv-abr-0903")
    gr = os.path.join("runs", "rv-grm-0902")
    # 패널마다 질문 하나. 행 = (연결 방식, rps, 기준 프리픽스, 추가 프리픽스)
    panels = [
        (T["q1"], T["q1sub"], "#2e6f9e", T["b1"], T["a1"], [
            (T["close"], 100, os.path.join(ab, "ab-direct-rps{r}"), os.path.join(ab, "ab-gw-rps{r}")),
            (T["close"], 200, os.path.join(ab, "ab-direct-rps{r}"), os.path.join(ab, "ab-gw-rps{r}")),
            (T["reuse"], 100, os.path.join(wk, "abr-direct-rps{r}"), os.path.join(wk, "abr-gw-rps{r}")),
            (T["reuse"], 200, os.path.join(wk, "abr-direct-rps{r}"), os.path.join(wk, "abr-gw-rps{r}")),
        ]),
        (T["q2"], T["q2sub"], "#6a4b9e", T["b2"], T["a2"], [
            (T["close"], 100, os.path.join(gr, "grm-off-close-rps{r}"), os.path.join(gr, "grm-on-close-rps{r}")),
            (T["close"], 200, os.path.join(gr, "grm-off-close-rps{r}"), os.path.join(gr, "grm-on-close-rps{r}")),
            (T["reuse"], 100, os.path.join(gr, "grm-off-reuse-rps{r}"), os.path.join(gr, "grm-on-reuse-rps{r}")),
            (T["reuse"], 200, os.path.join(gr, "grm-off-reuse-rps{r}"), os.path.join(gr, "grm-on-reuse-rps{r}")),
        ]),
    ]
    W, H = 920, 470
    PANW = 400
    ROWH = 58
    TOP = 152
    XMAXMS = 8.0
    AXW = 240.0
    s = svg_head(W, H)
    s.append(f'<text x="{W/2}" y="30" font-size="14.5" fill="#111" '
             f'text-anchor="middle" font-weight="bold">{T["c_title"]}</text>')
    s.append(f'<text x="{W/2}" y="50" font-size="11" fill="#777" '
             f'text-anchor="middle">{T["c_sub"]}</text>')
    for pi, (q, qsub, color, blabel, alabel, rows) in enumerate(panels):
        px = 26 + pi * (PANW + 60)
        ax0 = px + 96
        def X(ms):
            return ax0 + ms / XMAXMS * AXW
        s.append(f'<text x="{px+PANW/2}" y="84" font-size="12.5" fill="#111" '
                 f'text-anchor="middle" font-weight="bold">{q}</text>')
        s.append(f'<text x="{px+PANW/2}" y="100" font-size="10.5" fill="#666" '
                 f'text-anchor="middle">{qsub}</text>')
        # 범례: 기준 점과 추가 점
        s.append(f'<circle cx="{px+40}" cy="122" r="5" fill="#8a8f98"/>')
        s.append(f'<text x="{px+50}" y="126" font-size="10.5" fill="#333">{blabel}</text>')
        s.append(f'<circle cx="{px+210}" cy="122" r="5" fill="{color}"/>')
        s.append(f'<text x="{px+220}" y="126" font-size="10.5" fill="#333">{alabel}</text>')
        # 축 (절대 ms)
        for t in range(0, 9, 2):
            s.append(f'<line x1="{X(t):.1f}" y1="{TOP-8}" x2="{X(t):.1f}" '
                     f'y2="{TOP+len(rows)*ROWH-20}" stroke="#eee"/>')
            s.append(f'<text x="{X(t):.1f}" y="{TOP+len(rows)*ROWH-6}" font-size="9.5" '
                     f'fill="#999" text-anchor="middle">{t}</text>')
        s.append(f'<text x="{X(4):.1f}" y="{TOP+len(rows)*ROWH+10}" font-size="10" '
                 f'fill="#777" text-anchor="middle">p50 (ms)</text>')
        for ri, (mode, rps, base_p, add_p) in enumerate(rows):
            y = TOP + ri * ROWH
            b50, _ = med(study, base_p.format(r=rps))
            a50, _ = med(study, add_p.format(r=rps))
            d = a50 - b50
            xb, xa = X(b50), X(a50)
            s.append(f'<text x="{px}" y="{y+2}" font-size="11" fill="#333">{mode}</text>')
            s.append(f'<text x="{px}" y="{y+16}" font-size="10" fill="#888">{rps} rps</text>')
            s.append(f'<line x1="{xb:.1f}" y1="{y}" x2="{xa:.1f}" y2="{y}" '
                     f'stroke="{color}" stroke-width="4" opacity="0.45"/>')
            s.append(f'<circle cx="{xb:.1f}" cy="{y}" r="5.5" fill="#8a8f98"/>')
            s.append(f'<circle cx="{xa:.1f}" cy="{y}" r="5.5" fill="{color}"/>')
            s.append(f'<text x="{xb:.1f}" y="{y+21}" font-size="9.5" fill="#777" '
                     f'text-anchor="middle">{b50:.1f}</text>')
            s.append(f'<text x="{xa:.1f}" y="{y-11}" font-size="9.5" fill="{color}" '
                     f'text-anchor="middle" font-weight="bold">{a50:.1f}</text>')
            s.append(f'<text x="{px+PANW-8}" y="{y+5}" font-size="12.5" fill="#222" '
                     f'text-anchor="end" font-weight="bold">{d:+.1f}ms</text>')
        s.append(f'<text x="{px}" y="{TOP+len(rows)*ROWH+30}" font-size="10.5" '
                 f'fill="#555">{T["take1"] if pi==0 else T["take2"]}</text>')
    s.append("</svg>")
    return "\n".join(s)


def tail(study, T):
    """tail 보강 그림: p99 절대값(직접 대 게이트웨이, 연결 방식별, 로그 눈금). 원자료 runs/rv-tail-0903.
    (증분 행은 2026-09-07 사용자 판정으로 뺐다. 증분은 본문 표에 있다.)"""
    import math
    base = os.path.join(study, "runs", "rv-tail-0903")
    delays = [0, 10, 50, 200]
    modes = [("close", T["close"], "#2e6f9e"), ("reuse", T["reuse"], "#c0504d")]

    def med_abs(d, mode, arm, key):
        vals = [json.load(open(os.path.join(base, f"tail-d{d}-{mode}-{arm}-n{n}.json")))["latency_ms"][key]
                for n in range(1, 6) if os.path.exists(os.path.join(base, f"tail-d{d}-{mode}-{arm}-n{n}.json"))]
        return statistics.median(vals) if vals else 0.0

    def pair_med(d, mode, key):
        vals = []
        for n in range(1, 6):
            fd = os.path.join(base, f"tail-d{d}-{mode}-direct-n{n}.json")
            fg = os.path.join(base, f"tail-d{d}-{mode}-gw-n{n}.json")
            if os.path.exists(fd) and os.path.exists(fg):
                vals.append(json.load(open(fg))["latency_ms"][key] - json.load(open(fd))["latency_ms"][key])
        return statistics.median(vals) if vals else 0.0

    W, H = 920, 430
    PANW, PX0 = 400, 60
    s = svg_head(W, H)
    s.append(f'<text x="{W/2}" y="30" font-size="14.5" fill="#111" text-anchor="middle" font-weight="bold">{T["t_title"]}</text>')
    s.append(f'<text x="{W/2}" y="50" font-size="10.5" fill="#666" text-anchor="middle">{T["t_sub"]}</text>')

    def xpos(px, i):
        return px + 40 + i * (PANW - 80) / (len(delays) - 1)

    def xaxis(px, bot):
        for i, d in enumerate(delays):
            s.append(f'<text x="{xpos(px, i):.1f}" y="{bot + 18}" font-size="10" fill="#333" text-anchor="middle">{d}</text>')
        s.append(f'<text x="{px + PANW/2}" y="{bot + 34}" font-size="10" fill="#666" text-anchor="middle">{T["t_x"]}</text>')

    # ── 1행: p99 절대값, 직접 대 게이트웨이 (로그 눈금) ──
    s.append(f'<text x="{W/2}" y="78" font-size="12" fill="#111" text-anchor="middle" font-weight="bold">{T["t_abs"]}</text>')
    TOP1, BOT1 = 110, 330
    lo, hi = math.log10(5), math.log10(400)
    arms = [("gw", T["t_gw"], None), ("direct", T["t_direct"], "#8a8f98")]  # 점선(직접)을 위에 그린다
    for pi, (mode, mlabel, color) in enumerate(modes):
        px = PX0 + pi * (PANW + 60)
        s.append(f'<text x="{px + PANW/2}" y="{TOP1 - 10}" font-size="12" fill="{color}" text-anchor="middle" font-weight="bold">{mlabel}</text>')

        def Y(v):
            return BOT1 - (math.log10(v) - lo) / (hi - lo) * (BOT1 - TOP1)
        for t in (5, 10, 20, 50, 100, 200):
            s.append(f'<line x1="{px}" y1="{Y(t):.1f}" x2="{px + PANW}" y2="{Y(t):.1f}" stroke="#eee"/>')
            s.append(f'<text x="{px - 6}" y="{Y(t) + 4:.1f}" font-size="9.5" fill="#666" text-anchor="end">{t}ms</text>')
        xaxis(px, BOT1)
        series = {}
        for arm, alabel, acolor in arms:
            c = acolor or color
            series[arm] = [med_abs(d, mode, arm, "p99") for d in delays]
            pts = [(xpos(px, i), Y(v), v) for i, v in enumerate(series[arm])]
            path = " ".join(f'{"M" if i == 0 else "L"}{x:.1f},{y:.1f}' for i, (x, y, _) in enumerate(pts))
            dash = ' stroke-dasharray="6,4"' if arm == "direct" else ""
            s.append(f'<path d="{path}" fill="none" stroke="{c}" stroke-width="2.2"{dash}/>')
            for x, y, v in pts:
                r = 3.2 if arm == "direct" else 5.0
                s.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="{c}" stroke="white" stroke-width="1"/>')
        for i in range(len(delays)):
            dv, gv = series["direct"][i], series["gw"][i]
            x = xpos(px, i)
            # 두 값이 가까우면 한 줄에 "직접/게이트웨이"로, 멀면 각자 위아래
            if abs(math.log10(gv) - math.log10(dv)) < 0.06:
                s.append(f'<text x="{x:.1f}" y="{Y(max(dv, gv)) - 9:.1f}" font-size="9.5" fill="#333" text-anchor="middle">{dv:.1f} / {gv:.1f}</text>')
            else:
                hi_v, hi_c = (gv, color) if gv > dv else (dv, "#8a8f98")
                lo_v, lo_c = (dv, "#8a8f98") if gv > dv else (gv, color)
                s.append(f'<text x="{x:.1f}" y="{Y(hi_v) - 9:.1f}" font-size="9.5" fill="{hi_c}" text-anchor="middle">{hi_v:.1f}</text>')
                s.append(f'<text x="{x:.1f}" y="{Y(lo_v) + 16:.1f}" font-size="9.5" fill="{lo_c}" text-anchor="middle">{lo_v:.1f}</text>')
        lx, ly = px + PANW - 165, TOP1 + 6
        s.append(f'<line x1="{lx}" y1="{ly}" x2="{lx + 18}" y2="{ly}" stroke="#8a8f98" stroke-width="2.2" stroke-dasharray="5,3"/>')
        s.append(f'<text x="{lx + 24}" y="{ly + 4}" font-size="10" fill="#333">{T["t_direct"]}</text>')
        s.append(f'<line x1="{lx}" y1="{ly + 16}" x2="{lx + 18}" y2="{ly + 16}" stroke="{color}" stroke-width="2.2"/>')
        s.append(f'<text x="{lx + 24}" y="{ly + 20}" font-size="10" fill="#333">{T["t_gw"]}</text>')

    s.append(f'<text x="{W/2}" y="{H - 22}" font-size="10.5" fill="#555" text-anchor="middle">{T["t_take"]}</text>')
    s.append("</svg>")
    return "\n".join(s)

def value(T):
    """도입 효과 그림: 경로 안의 게이트웨이(로고), 얻는 것과 내는 것. 로고 = figures/_agentgateway-logo.svg
    (agentgateway 저장소 ui/public/logo.svg, Apache 2.0)."""
    import re
    W, H = 920, 560
    s = svg_head(W, H)
    logo_path = os.path.join("figures", "_agentgateway-logo.svg")
    logo_inner = ""
    if os.path.exists(logo_path):
        raw = open(logo_path).read()
        m = re.search(r"<svg[^>]*>(.*)</svg>", raw, re.S)
        if m:
            logo_inner = re.sub(r'<rect[^>]*fill="white"[^>]*/>', "", m.group(1), count=1)

    def box(x, y, w, h, label, fill="#fafafa", stroke="#999", size=11, bold=False):
        s.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" fill="{fill}" stroke="{stroke}" stroke-width="1.4"/>')
        lines = label.split("\n")
        y0 = y + h / 2 - (len(lines) - 1) * 8
        for i, ln in enumerate(lines):
            fw = ' font-weight="bold"' if (bold and i == 0) else ""
            s.append(f'<text x="{x + w/2}" y="{y0 + i*16 + 4}" font-size="{size}" fill="#222" text-anchor="middle"{fw}>{ln}</text>')

    def arrow(x1, y1, x2, y2, color="#555", dash=""):
        import math
        d = f' stroke-dasharray="{dash}"' if dash else ""
        s.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="2"{d}/>')
        ang = math.atan2(y2 - y1, x2 - x1)
        for da in (2.6, -2.6):
            s.append(f'<line x1="{x2}" y1="{y2}" x2="{x2 - 9*math.cos(ang+da):.1f}" y2="{y2 - 9*math.sin(ang+da):.1f}" stroke="{color}" stroke-width="2"/>')

    s.append(f'<text x="{W/2}" y="30" font-size="14.5" fill="#111" text-anchor="middle" font-weight="bold">{T["v_title"]}</text>')
    s.append(f'<text x="{W/2}" y="50" font-size="10.5" fill="#666" text-anchor="middle">{T["v_sub"]}</text>')
    # 경로: 클라이언트 -> 게이트웨이 -> 서버
    CY = 250
    box(40, CY - 32, 150, 64, T["v_client"], fill="#eef3f8", stroke="#2e6f9e", bold=True)
    gx, gy, gw, gh = 300, CY - 62, 320, 124
    s.append(f'<rect x="{gx}" y="{gy}" width="{gw}" height="{gh}" rx="10" fill="#f6f3fb" stroke="#6a4b9e" stroke-width="2"/>')
    if logo_inner:
        s.append(f'<svg x="{gx + 30}" y="{gy + 14}" width="{gw - 60}" height="{(gw - 60) * 1064 / 4496:.1f}" viewBox="0 0 4496 1064">{logo_inner}</svg>')
    else:
        s.append(f'<text x="{gx + gw/2}" y="{gy + 50}" font-size="18" fill="#6a4b9e" text-anchor="middle" font-weight="bold">agentgateway</text>')
    s.append(f'<text x="{gx + gw/2}" y="{gy + gh - 14}" font-size="10.5" fill="#444" text-anchor="middle">{T["v_proxy"]}</text>')
    box(730, CY - 62, 150, 52, T["v_server"], fill="#eef7ee", stroke="#3c8d5a", bold=True)
    box(730, CY + 10, 150, 52, T["v_agent"], fill="#eef7ee", stroke="#3c8d5a", bold=True)
    arrow(190, CY, 300, CY, color="#2e6f9e")
    arrow(620, CY - 20, 730, CY - 36, color="#6a4b9e")
    arrow(620, CY + 20, 730, CY + 36, color="#6a4b9e")
    s.append(f'<text x="245" y="{CY - 10}" font-size="10" fill="#2e6f9e" text-anchor="middle">{T["v_gw"]}</text>')
    # 직접 호출(대조군): 게이트웨이 위로 우회하는 점선
    s.append(f'<path d="M115,{CY - 32} C115,120 805,120 805,{CY - 62}" fill="none" stroke="#8a8f98" stroke-width="1.8" stroke-dasharray="6,4"/>')
    s.append(f'<text x="460" y="112" font-size="10" fill="#8a8f98" text-anchor="middle">{T["v_direct"]}</text>')
    # 얻는 것 / 내는 것
    y = 350
    s.append(f'<text x="60" y="{y}" font-size="12" fill="#3c8d5a" font-weight="bold">{T["v_gain_h"]}</text>')
    for i, g in enumerate(T["v_gains"]):
        s.append(f'<text x="70" y="{y + 22 + i*19}" font-size="11" fill="#222">+ {g}</text>')
    s.append(f'<text x="500" y="{y}" font-size="12" fill="#c0504d" font-weight="bold">{T["v_cost_h"]}</text>')
    for i, c in enumerate(T["v_costs"]):
        s.append(f'<text x="510" y="{y + 22 + i*19}" font-size="11" fill="#222">- {c}</text>')
    s.append(f'<line x1="40" y1="{H - 62}" x2="{W - 40}" y2="{H - 62}" stroke="#eee"/>')
    s.append(f'<text x="{W/2}" y="{H - 40}" font-size="10.5" fill="#555" text-anchor="middle">{T["v_caveat"]}</text>')
    s.append("</svg>")
    return "\n".join(s)


def arch(T):
    """측정 구조도. 호스트(부하, 프로브) -> 클러스터(게이트웨이, 정책, guardrail, 백엔드, 탭)."""
    W, H = 920, 520
    s = svg_head(W, H)

    def box(x, y, w, h, label, fill="#fafafa", stroke="#999", size=11, bold=False, color="#222"):
        s.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" fill="{fill}" stroke="{stroke}" stroke-width="1.4"/>')
        lines = label.split("\n")
        y0 = y + h / 2 - (len(lines) - 1) * 8
        for i, ln in enumerate(lines):
            fw = ' font-weight="bold"' if (bold and i == 0) else ""
            s.append(f'<text x="{x + w/2}" y="{y0 + i*16 + 4}" font-size="{size}" fill="{color}" text-anchor="middle"{fw}>{ln}</text>')

    def arrow(x1, y1, x2, y2, color="#555", dash="", label=None, lx=None, ly=None):
        d = f' stroke-dasharray="{dash}"' if dash else ""
        s.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="1.8"{d}/>')
        import math
        ang = math.atan2(y2 - y1, x2 - x1)
        for da in (2.6, -2.6):
            s.append(f'<line x1="{x2}" y1="{y2}" x2="{x2 - 9*math.cos(ang+da):.1f}" y2="{y2 - 9*math.sin(ang+da):.1f}" stroke="{color}" stroke-width="1.8"/>')
        if label:
            s.append(f'<text x="{lx}" y="{ly}" font-size="10" fill="{color}" text-anchor="middle">{label}</text>')

    s.append(f'<text x="{W/2}" y="30" font-size="14.5" fill="#111" text-anchor="middle" font-weight="bold">{T["a_title"]}</text>')
    s.append(f'<text x="{W/2}" y="50" font-size="10.5" fill="#666" text-anchor="middle">{T["a_sub"]}</text>')
    # 호스트
    s.append('<rect x="30" y="80" width="200" height="380" rx="8" fill="none" stroke="#bbb" stroke-dasharray="6,4"/>')
    s.append(f'<text x="130" y="100" font-size="11.5" fill="#444" text-anchor="middle" font-weight="bold">{T["a_host"]}</text>')
    box(50, 130, 160, 60, T["a_loadgen"], fill="#eef3f8", stroke="#2e6f9e")
    box(50, 330, 160, 60, T["a_probe"], fill="#eef3f8", stroke="#2e6f9e")
    # 클러스터
    s.append('<rect x="270" y="80" width="620" height="380" rx="8" fill="none" stroke="#bbb" stroke-dasharray="6,4"/>')
    s.append(f'<text x="580" y="100" font-size="11.5" fill="#444" text-anchor="middle" font-weight="bold">{T["a_cluster"]}</text>')
    box(300, 120, 200, 48, T["a_cp"], fill="#f3f0f8", stroke="#6a4b9e", size=10.5)
    box(300, 215, 200, 60, T["a_proxy"], fill="#f3f0f8", stroke="#6a4b9e", bold=True)
    box(300, 330, 200, 66, T["a_policy"], fill="#f3f0f8", stroke="#6a4b9e", size=10.5)
    box(540, 340, 160, 56, T["a_gr"], fill="#fbf1f1", stroke="#c0504d", size=10.5)
    box(660, 205, 200, 60, T["a_backend"], fill="#eef7ee", stroke="#3c8d5a", bold=True)
    box(660, 120, 200, 48, T["a_tap"], fill="#eef7ee", stroke="#3c8d5a", size=10.5)
    # 화살표
    arrow(400, 168, 400, 215, color="#6a4b9e", dash="4,3")
    arrow(400, 330, 400, 275, color="#6a4b9e", dash="4,3")
    arrow(210, 160, 300, 245, color="#2e6f9e", label=T["a_gw"], lx=250, ly=195)
    arrow(210, 160, 660, 225, color="#8a8f98", dash="6,4", label=T["a_direct"], lx=470, ly=182)
    arrow(500, 245, 660, 235, color="#6a4b9e")
    arrow(500, 363, 540, 368, color="#c0504d", dash="4,3", label=T["a_grpc"], lx=520, ly=420)
    arrow(210, 360, 300, 260, color="#2e6f9e")
    arrow(760, 205, 760, 168, color="#3c8d5a", dash="4,3")
    s.append(f'<text x="{W/2}" y="{H - 22}" font-size="10.5" fill="#555" text-anchor="middle">{T["a_cap"]}</text>')
    s.append("</svg>")
    return "\n".join(s)


def reject(T):
    W, H = 760, 580
    s = svg_head(W, H)
    s.append(f'<text x="{W/2}" y="30" font-size="14" fill="#111" '
             f'text-anchor="middle" font-weight="bold">{T["r_title"]}</text>')
    s.append(f'<text x="{W/2}" y="48" font-size="11" fill="#777" '
             f'text-anchor="middle">{T["r_sub"]}</text>')

    C1, C2, C3 = "#c1442e", "#6a4b9e", "#8a6d1f"

    def box(x, y, w, h, label, sub=None, stroke="#999"):
        s.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" '
                 f'fill="#fafafa" stroke="{stroke}" stroke-width="1.5"/>')
        ly = y + (h / 2 + 4 if sub is None else h / 2 - 4)
        s.append(f'<text x="{x + w / 2}" y="{ly}" font-size="12" fill="#222" '
                 f'text-anchor="middle" font-weight="bold">{label}</text>')
        if sub:
            s.append(f'<text x="{x + w / 2}" y="{y + h / 2 + 14}" font-size="9.5" '
                     f'fill="#666" text-anchor="middle">{sub}</text>')

    def arrow(x1, y1, x2, y2):
        s.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" '
                 f'stroke="#555" stroke-width="1.8"/>')
        import math
        ang = math.atan2(y2 - y1, x2 - x1)
        for da in (2.6, -2.6):
            s.append(f'<line x1="{x2}" y1="{y2}" '
                     f'x2="{x2 + 9 * math.cos(ang + da):.1f}" '
                     f'y2="{y2 + 9 * math.sin(ang + da):.1f}" '
                     f'stroke="#555" stroke-width="1.8"/>')

    def marker(x, y, n, color):
        s.append(f'<circle cx="{x}" cy="{y}" r="11" fill="{color}"/>')
        s.append(f'<text x="{x}" y="{y + 4}" font-size="12" fill="white" '
                 f'text-anchor="middle" font-weight="bold">{n}</text>')

    # 경로 지형도
    box(40, 120, 110, 44, T["p_client"])
    box(280, 106, 170, 72, T["p_gw"], T["p_authz"])
    box(560, 120, 150, 44, T["p_srv"])
    arrow(150, 142, 278, 142)
    arrow(450, 142, 558, 142)
    # guardrail 서버와 gRPC 링크
    box(280, 252, 170, 44, T["p_gr"])
    s.append('<line x1="365" y1="178" x2="365" y2="250" stroke="#555" '
             'stroke-width="1.8" stroke-dasharray="4,3"/>')
    s.append(f'<text x="384" y="218" font-size="9.5" fill="#666">{T["p_grpc"]}</text>')
    # 거부 지점 마커
    s.append(f'<line x1="352" y1="228" x2="378" y2="200" stroke="{C3}" stroke-width="2.5"/>')
    marker(292, 118, "1", C1)      # 게이트웨이 안 인가 정책
    marker(292, 252, "2", C2)      # guardrail 서버의 거부 판정
    marker(365, 214, "3", C3)      # 링크 단절(서버 불달)
    s.append(f'<text x="{W / 2}" y="326" font-size="10.5" fill="#555" '
             f'text-anchor="middle">{T["p_cap"]}</text>')

    # 형태 카드 3장
    cols = [
        ("1", T["r1h"], T["r1b"], T["r1n"], C1),
        ("2", T["r2h"], T["r2b"], T["r2n"], C2),
        ("3", T["r3h"], T["r3b"], T["r3n"], C3),
    ]
    cw, cy = 224, 348
    for i, (num, head, body, note, color) in enumerate(cols):
        x = 24 + i * (cw + 20)
        s.append(f'<rect x="{x}" y="{cy}" width="{cw}" height="200" rx="8" '
                 f'fill="none" stroke="{color}" stroke-width="2"/>')
        s.append(f'<rect x="{x}" y="{cy}" width="{cw}" height="38" rx="8" fill="{color}"/>')
        s.append(f'<rect x="{x}" y="{cy + 24}" width="{cw}" height="14" fill="{color}"/>')
        s.append(f'<text x="{x + cw / 2}" y="{cy + 24}" font-size="12.5" fill="white" '
                 f'text-anchor="middle" font-weight="bold">{num}. {head}</text>')
        for li, line in enumerate(body.split("\n")):
            s.append(f'<text x="{x + cw / 2}" y="{cy + 70 + li * 20}" font-size="12.5" '
                     f'fill="#222" text-anchor="middle" '
                     f'font-family="Menlo, monospace">{line}</text>')
        for li, line in enumerate(note.split("\n")):
            s.append(f'<text x="{x + cw / 2}" y="{cy + 136 + li * 17}" font-size="11" '
                     f'fill="#555" text-anchor="middle">{line}</text>')
    s.append("</svg>")
    return "\n".join(s)


if __name__ == "__main__":
    study, kind = sys.argv[1], sys.argv[2]
    lang = sys.argv[3] if len(sys.argv) > 3 else "en"
    T = TEXT[lang]
    if kind == "cost":
        print(cost(study, T))
    elif kind == "tail":
        print(tail(study, T))
    elif kind == "arch":
        print(arch(T))
    elif kind == "value":
        print(value(T))
    else:
        print(reject(T))
