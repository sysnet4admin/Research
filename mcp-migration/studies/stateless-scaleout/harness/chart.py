#!/usr/bin/env python3
"""발행용 차트 2종 생성 (cni-benchmark chart.py 선례).

1. scaleout: replica 1/2/4에서 A(close/reuse)와 B의 실제 처리량 꺾은선
2. handles:  stateless 스펙의 handle 설계 3종 막대

수치는 runs 디렉토리의 셀 JSON에서 직접 계산한다(반복 중앙값, 유실은 3회 합).

사용: python3 harness/chart.py <runs_dir> <scaleout|handles> [en|ko] > out.svg
"""

import glob
import json
import os
import statistics
import sys


def cell(runs, prefix, *extra_runs):
    """셀 하나의 (중앙값, 세션유실합, 핸들유실합, 최소, 최대)를 낸다.

    extra_runs 로 보강 캠페인 관측을 같은 셀에 합친다(여러 개 줄 수 있다).
    구 스펙 셀은 회차 편차가 커서 중앙값만으로는 오해를 부르므로 범위를 함께
    그린다. 합산은 전체 관측을 한 묶음으로 보고 중앙값을 낸다.
    """
    rps, sloss, hloss = [], 0, 0
    patterns = [os.path.join(runs, prefix + "-rep*.json")]
    patterns += [e for e in extra_runs if e]
    for pat in patterns:
        for f in sorted(glob.glob(pat)):
            if f.endswith(".kill.json"):
                continue
            d = json.load(open(f))
            rps.append(d["achieved_rps"])
            sloss += d["session_loss"]
            hloss += d["handle_loss"]
    return statistics.median(rps), sloss, hloss, min(rps), max(rps)


TEXT = {
    "ko": {
        "sc_title": "스케일아웃: 목표 200rps 중 실제 처리량 (중앙값, 띠는 회차 범위)",
        "sc_x": "레플리카 수", "sc_y": "달성 rps",
        "sc_a_close": "구 스펙 (연결 매번 새로)", "sc_a_reuse": "구 스펙 (연결 재사용)",
        "sc_b": "신 스펙 (스테이트리스)", "sc_target": "목표 200rps",
        "sc_loss": "세션 유실", "cnt": "건",
        "h_title": "스테이트리스 스펙의 핸들 설계 3종 (목표 100rps, 30초 x 3회)",
        "h_y": "달성 rps",
        "h_mem": "파드 메모리", "h_hmac": "HMAC 서명", "h_redis": "외부 저장 (Redis)",
        "h_loss": "핸들 유실",
    },
    "en": {
        "sc_title": "Scale-out: what gets through at 200 rps offered (median, band = run range)",
        "sc_x": "replicas", "sc_y": "achieved rps",
        "sc_a_close": "old spec (new conn per call)", "sc_a_reuse": "old spec (conn reuse)",
        "sc_b": "new spec (stateless)", "sc_target": "offered 200 rps",
        "sc_loss": "session losses", "cnt": "",
        "h_title": "Three handle designs under the stateless spec (100 rps offered, 30s x 3)",
        "h_y": "achieved rps",
        "h_mem": "pod memory", "h_hmac": "self-contained (HMAC)", "h_redis": "external (Redis)",
        "h_loss": "handle losses",
    },
}


def svg_head(w, h):
    return [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" '
            f'font-family="Helvetica, Arial, sans-serif">',
            f'<rect width="{w}" height="{h}" fill="white"/>']


def scaleout(runs, T):
    """본측정 3회에 보강 주간 관측을 합쳐 그린다.

    구 스펙 셀은 회차 편차가 커서 3회 중앙값이 분포의 아래쪽을 잡는 일이 있었다
    (close r2는 98.9로 나왔다가 13회로는 116.5). 그래서 v3 고반복분을 합산하고
    범위를 띠로 함께 그린다 (2026-08-18).
    """
    base = os.path.dirname(runs.rstrip("/"))
    v3 = os.path.join(base, "week-2026-08-10", "v3-highrep")
    wk = os.path.join(base, "weekend-2026-08-08", "w1-a-reuse-r4-rep*.json")

    a_close = [cell(runs, f"m1-a-echo-close-r{r}",
                    os.path.join(v3, f"v3-a-close-r{r}-rep*.json")) for r in (1, 2, 4)]
    # 재사용 r4만 8/8 보강분(w1)이 더 있다
    a_reuse = [cell(runs, f"m1-a-echo-reuse-r{r}",
                    os.path.join(v3, f"v3-a-reuse-r{r}-rep*.json"),
                    wk if r == 4 else None) for r in (1, 2, 4)]
    b_close = [cell(runs, f"m1-b-echo-close-r{r}",
                    os.path.join(v3, f"v3-b-close-r{r}-rep*.json")) for r in (1, 2, 4)]

    W, H = 700, 430
    ML, MR, MT, MB = 64, 210, 52, 56
    PW, PH = W - ML - MR, H - MT - MB
    xs = {1: ML + PW * 0.08, 2: ML + PW * 0.5, 4: ML + PW * 0.92}

    def Y(v):
        return MT + PH - v / 220.0 * PH

    s = svg_head(W, H)
    s.append(f'<text x="{ML+PW/2}" y="26" font-size="13" fill="#111" '
             f'text-anchor="middle" font-weight="bold">{T["sc_title"]}</text>')
    for gy in range(0, 201, 50):
        s.append(f'<line x1="{ML}" y1="{Y(gy)}" x2="{ML+PW}" y2="{Y(gy)}" stroke="#e8e8e8"/>')
        s.append(f'<text x="{ML-8}" y="{Y(gy)+4}" font-size="11" fill="#666" '
                 f'text-anchor="end">{gy}</text>')
    s.append(f'<line x1="{ML}" y1="{Y(200)}" x2="{ML+PW}" y2="{Y(200)}" '
             f'stroke="#999" stroke-dasharray="5,4"/>')
    s.append(f'<text x="{ML+PW-6}" y="{Y(200)+16}" font-size="10" fill="#777" '
             f'text-anchor="end">{T["sc_target"]}</text>')
    s.append(f'<rect x="{ML}" y="{MT}" width="{PW}" height="{PH}" fill="none" stroke="#999"/>')
    for r in (1, 2, 4):
        s.append(f'<text x="{xs[r]}" y="{MT+PH+18}" font-size="11" fill="#333" '
                 f'text-anchor="middle">{r}</text>')
    s.append(f'<text x="{ML+PW/2}" y="{H-14}" font-size="12" fill="#333" '
             f'text-anchor="middle">{T["sc_x"]}</text>')
    s.append(f'<text x="20" y="{MT+PH/2}" font-size="12" fill="#333" text-anchor="middle" '
             f'transform="rotate(-90 20 {MT+PH/2})">{T["sc_y"]}</text>')

    series = [
        (a_close, "#c1442e", T["sc_a_close"], "0,0"),
        (a_reuse, "#d98e6a", T["sc_a_reuse"], "6,4"),
        (b_close, "#2e6f9e", T["sc_b"], "0,0"),
    ]
    # 회차 범위를 세로 막대로 먼저 깔아 둔다 (선과 점보다 아래에)
    for vals, color, _label, _dash in series:
        for r, v in zip((1, 2, 4), vals):
            if v[4] - v[3] < 1.0:
                continue
            s.append(f'<line x1="{xs[r]:.1f}" y1="{Y(v[3]):.1f}" '
                     f'x2="{xs[r]:.1f}" y2="{Y(v[4]):.1f}" stroke="{color}" '
                     f'stroke-width="7" opacity="0.22" stroke-linecap="round"/>')

    for vals, color, _label, dash in series:
        pts = " ".join(f"{xs[r]:.1f},{Y(v[0]):.1f}" for r, v in zip((1, 2, 4), vals))
        extra = f' stroke-dasharray="{dash}"' if dash != "0,0" else ""
        s.append(f'<polyline points="{pts}" fill="none" stroke="{color}" stroke-width="2.5"{extra}/>')
        for r, v in zip((1, 2, 4), vals):
            s.append(f'<circle cx="{xs[r]:.1f}" cy="{Y(v[0]):.1f}" r="5" fill="{color}"/>')

    # 값 라벨 (겹침 회피: B는 위, A close는 아래, A reuse는 중간 오른쪽)
    for r, v in zip((2, 4), b_close[1:]):
        s.append(f'<text x="{xs[r]:.1f}" y="{Y(v[0])-10:.1f}" font-size="11" fill="#2e6f9e" '
                 f'text-anchor="middle" font-weight="bold">{v[0]:.0f}</text>')
    for r, v in zip((2, 4), a_close[1:]):
        s.append(f'<text x="{xs[r]:.1f}" y="{Y(v[0])+22:.1f}" font-size="11" fill="#c1442e" '
                 f'text-anchor="middle">{v[0]:.1f}</text>')
        s.append(f'<text x="{xs[r]:.1f}" y="{Y(v[0])+36:.1f}" font-size="10" fill="#c1442e" '
                 f'text-anchor="middle">{T["sc_loss"]} {v[1]:,}{T["cnt"]}</text>')
    for r, v in zip((2, 4), a_reuse[1:]):
        s.append(f'<text x="{xs[r]+12:.1f}" y="{Y(v[0])+4:.1f}" font-size="11" '
                 f'fill="#b5764f">{v[0]:.1f}</text>')

    lx, ly = ML + PW + 16, MT + 8
    for i, (_v, color, label, dash) in enumerate(series):
        y = ly + i * 22
        extra = f' stroke-dasharray="{dash}"' if dash != "0,0" else ""
        s.append(f'<line x1="{lx}" y1="{y}" x2="{lx+22}" y2="{y}" stroke="{color}" '
                 f'stroke-width="2.5"{extra}/>')
        s.append(f'<text x="{lx+28}" y="{y+4}" font-size="11" fill="#333">{label}</text>')
    s.append("</svg>")
    return "\n".join(s)


def handles(runs, T):
    data = [
        (T["h_mem"], cell(runs, "m2-b-mem"), "#8a8f98"),
        (T["h_hmac"], cell(runs, "m2-b-hmac"), "#2e6f9e"),
        (T["h_redis"], cell(runs, "m2-b-redis"), "#3a7d44"),
    ]
    W, H = 640, 400
    ML, MR, MT, MB = 60, 24, 52, 84
    PW, PH = W - ML - MR, H - MT - MB
    ymax = 120.0

    def Y(v):
        return MT + PH - v / ymax * PH

    s = svg_head(W, H)
    s.append(f'<text x="{ML+PW/2}" y="26" font-size="13" fill="#111" '
             f'text-anchor="middle" font-weight="bold">{T["h_title"]}</text>')
    for gy in range(0, 101, 25):
        s.append(f'<line x1="{ML}" y1="{Y(gy)}" x2="{ML+PW}" y2="{Y(gy)}" stroke="#e8e8e8"/>')
        s.append(f'<text x="{ML-8}" y="{Y(gy)+4}" font-size="11" fill="#666" '
                 f'text-anchor="end">{gy}</text>')
    s.append(f'<line x1="{ML}" y1="{Y(100)}" x2="{ML+PW}" y2="{Y(100)}" '
             f'stroke="#999" stroke-dasharray="5,4"/>')
    s.append(f'<text x="20" y="{MT+PH/2}" font-size="12" fill="#333" text-anchor="middle" '
             f'transform="rotate(-90 20 {MT+PH/2})">{T["h_y"]}</text>')

    bw = 70
    for i, (label, (rps, _sl, hl, _lo, _hi), color) in enumerate(data):
        cx = ML + PW * (i + 0.5) / 3
        s.append(f'<rect x="{cx-bw/2:.1f}" y="{Y(rps):.1f}" width="{bw}" '
                 f'height="{PH-(Y(rps)-MT):.1f}" fill="{color}"/>')
        s.append(f'<text x="{cx:.1f}" y="{Y(rps)-8:.1f}" font-size="12" fill="#333" '
                 f'text-anchor="middle" font-weight="bold">{rps:.1f}</text>')
        s.append(f'<text x="{cx:.1f}" y="{MT+PH+20}" font-size="11" fill="#333" '
                 f'text-anchor="middle">{label}</text>')
        loss_color = "#c1442e" if hl else "#666"
        s.append(f'<text x="{cx:.1f}" y="{MT+PH+42}" font-size="11" fill="{loss_color}" '
                 f'text-anchor="middle">{T["h_loss"]} {hl:,}{T["cnt"]}</text>')
    s.append("</svg>")
    return "\n".join(s)


if __name__ == "__main__":
    runs, kind = sys.argv[1], sys.argv[2]
    lang = sys.argv[3] if len(sys.argv) > 3 else "en"
    T = TEXT[lang]
    print(scaleout(runs, T) if kind == "scaleout" else handles(runs, T))
