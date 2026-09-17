#!/usr/bin/env python3
"""캠페인 출력을 표로 모은다. 사이클 사이에 결과가 흔들리면 그것도 보이게 한다.

셀마다 사이클별 판정을 모으고, 전 사이클에서 같으면 한 줄로, 다르면 갈라서 적는다.
"""
import argparse, collections, glob, json, os, statistics, sys

CELL_DESC = {}


def load_desc(study):
    p = os.path.join(study, "harness", "cells", "index.json")
    if os.path.exists(p):
        CELL_DESC.update(json.load(open(p)))


def cell_rows(out):
    """셀 -> 사이클 목록 -> 판정"""
    rows = collections.defaultdict(list)
    for f in sorted(glob.glob(os.path.join(out, "c*-*.json"))):
        base = os.path.basename(f)
        if "-trace-" in base or base.startswith("axis5"):
            continue
        try:
            d = json.load(open(f))
        except json.JSONDecodeError:
            continue
        if "probes" not in d:
            continue
        cyc = base.split("-", 1)[0][1:]
        p = d["probes"]
        rows[d["cell"]].append({
            "cycle": int(cyc) if cyc.isdigit() else 0,
            "n_tools": p["list"]["n_tools"],
            "tools": tuple(p["list"]["tools"]),
            "a1": p["sum_a1"]["verdict"], "a2": p["sum_a2"]["verdict"],
            "echo": p["echo"]["verdict"],
            "p50": p["sum_a1"]["p50_ms"],
        })
    return rows


def fmt_cells(rows):
    print("## 셀별 판정\n")
    print("| 셀 | 설명 | 사이클 | 목록 | a=1 | a=2 | echo | p50(ms) |")
    print("|---|---|---|---|---|---|---|---|")
    for cell in sorted(rows, key=lambda c: (c[0], int("".join(filter(str.isdigit, c)) or 0))):
        rs = rows[cell]
        sig = collections.Counter((r["n_tools"], r["a1"], r["a2"], r["echo"]) for r in rs)
        for (nt, a1, a2, ec), cnt in sig.most_common():
            ps = [r["p50"] for r in rs if (r["n_tools"], r["a1"], r["a2"], r["echo"]) == (nt, a1, a2, ec)]
            p50 = round(statistics.median(ps), 2) if ps else None
            stable = "" if len(sig) == 1 else " (갈림)"
            print(f"| {cell} | {CELL_DESC.get(cell,'')[:38]} | {cnt}회{stable} | {nt}개 | {a1} | {a2} | {ec} | {p50} |")


def fmt_load(out):
    files = sorted(glob.glob(os.path.join(out, "load-*.json")))
    if not files:
        return
    agg = collections.defaultdict(list)
    for f in files:
        d = json.load(open(f))
        agg[d["label"]].append(d)
    print("\n## 부하\n")
    print("| 조건 | 회차 | rps(중앙) | p50(중앙) | p95(중앙) | 오류 |")
    print("|---|---|---|---|---|---|")
    for label in sorted(agg):
        ds = agg[label]
        med = lambda k: round(statistics.median([x[k] for x in ds if x.get(k) is not None]), 2)
        print(f"| {label} | {len(ds)} | {med('rps')} | {med('p50')} | {med('p95')} | "
              f"{sum(x['err'] for x in ds)} |")


def fmt_rate(out):
    files = sorted(glob.glob(os.path.join(out, "rate-*.json")))
    if not files:
        return
    agg = collections.defaultdict(list)
    for f in files:
        d = json.load(open(f))
        agg[d["label"]].append(d)
    print("\n## 폐루프 짝 증분 (목표 rps 고정)\n")
    print("| 조건 | 회차 | 목표 | 달성(중앙) | p50 | p99 | shed | 오류 |")
    print("|---|---|---|---|---|---|---|---|")
    for label in sorted(agg):
        ds = agg[label]
        med = lambda k: (round(statistics.median([x[k] for x in ds if x.get(k) is not None]), 2)
                         if any(x.get(k) is not None for x in ds) else None)
        print(f"| {label} | {len(ds)} | {ds[0]['rate_target']} | {med('rate_achieved')} | "
              f"{med('p50')} | {med('p99')} | {sum(x['shed'] for x in ds)} | "
              f"{sum(x['err'] for x in ds)} |")


def fmt_trace(out):
    gw = sorted(glob.glob(os.path.join(out, "*-trace-gw.json")))
    dr = sorted(glob.glob(os.path.join(out, "*-trace-direct.json")))
    if not gw:
        return
    print("\n## 트레이스 전파\n")
    print("| 경로 | 케이스 | 백엔드가 받은 traceparent | params._meta |")
    print("|---|---|---|---|")
    for name, files in (("게이트웨이", gw), ("직접", dr)):
        if not files:
            continue
        d = json.load(open(files[-1]))
        for case, v in d["cases"].items():
            tp = v["backend_traceparent"]
            meta = "있음" if v["params_meta"] else "없음"
            print(f"| {name} | {case} | {tp or '없음'} | {meta} |")


def fmt_axis5(out):
    files = sorted(glob.glob(os.path.join(out, "axis5-c*.json")))
    if not files:
        return
    print("\n## 축 5\n")
    d = json.load(open(files[-1]))
    print("| 클라이언트가 요청한 protocolVersion | 게이트웨이가 돌려준 값 |")
    print("|---|---|")
    for k, v in d.get("protocol_negotiation", {}).items():
        print(f"| {k} | {v} |")
    print(f"\ncharset 붙인 Content-Type: HTTP {d.get('charset_content_type_code')}, "
          f"붙이지 않음: HTTP {d.get('plain_content_type_code')} "
          f"(사이클 {len(files)}회 관측)")


def fmt_health(out):
    """재시작은 캠페인 시작 시점 대비 증가분만 본다. 오래된 재시작은 잡음이다."""
    def key(f):
        b = os.path.basename(f)
        return int("".join(filter(str.isdigit, b)) or 0)

    files = sorted(glob.glob(os.path.join(out, "res-c*.txt")), key=key)
    if not files:
        return

    def counts(f):
        out_ = {}
        for line in open(f, errors="replace"):
            if line.startswith("재시작:"):
                parts = line.split()
                if len(parts) >= 6:
                    out_[parts[1] + "/" + parts[2]] = parts[5]
        return out_

    base = counts(files[0])
    last = counts(files[-1])
    grew = [(k, base.get(k, "0"), v) for k, v in last.items() if base.get(k) != v]
    print(f"\n## 상태\n\n자원 기록 {len(files)}회(사이클 {key(files[0])}~{key(files[-1])}). "
          f"캠페인 중 재시작이 늘어난 파드 {len(grew)}개.")
    for k, b, v in grew[:15]:
        print(f"- {k}: {b} -> {v}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    a = ap.parse_args()
    study = os.path.dirname(os.path.dirname(os.path.abspath(a.out.rstrip("/"))))
    load_desc(study)
    rows = cell_rows(a.out)
    cyc = max((r["cycle"] for rs in rows.values() for r in rs), default=0)
    print(f"# 캠페인 판독: {os.path.basename(a.out)}\n")
    print(f"사이클 {cyc}회. 셀 {len(rows)}종.\n")
    fmt_cells(rows)
    fmt_load(a.out)
    fmt_rate(a.out)
    fmt_trace(a.out)
    fmt_axis5(a.out)
    fmt_health(a.out)
