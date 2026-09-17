#!/usr/bin/env python3
"""그림 SVG에서 글자가 상자를 넘치거나 화면 밖으로 나가는지 검사한다.

손으로 렌더링해 보고 찾는 대신 생성 직후 걸러 내려고 만들었다. 텍스트의 표시 너비를
글꼴 크기로 어림해 가장 가까운 상자와 비교한다. 어림이라 경계에 걸리는 것은 눈으로
한 번 더 본다.
"""
import glob
import re
import sys
import unicodedata

W = 900


def dwidth(t):
    return sum(2 if unicodedata.east_asian_width(c) in ("W", "F") else 1 for c in t)


def approx(text, size, mono):
    # 폭 계수는 렌더링 결과와 맞춰 잡은 값이다. mono 가 조금 더 넓다.
    return dwidth(text) * size * (0.52 if mono else 0.47)


def check_labels(path, s, rects):
    """선 위 라벨(흰 사각형 + 글자)이 옆 상자를 덮는지 본다. 글자 넘침 검사는
    가장 가까운 상자와만 비교해서 이 겹침을 놓친다. 영문 라벨이 길어져 상자
    글자를 가린 적이 있다."""
    import re
    bad = []
    bad += check_labels(path, s, rects)
    # 라벨은 흰색 채움에 테두리가 없는 사각형이다.
    for m in re.finditer(r'<rect x="([0-9.-]+)" y="([0-9.-]+)" width="([0-9.]+)" height="([0-9.]+)" fill="white"/>', s):
        lx, ly, lw, lh = (float(m.group(i)) for i in (1, 2, 3, 4))
        if lw > 300:  # 바탕 사각형은 건너뛴다
            continue
        for bx, by, bw, bh in rects:
            if bw > 300 or bh > 200:  # 큰 테두리 상자는 건너뛴다
                continue
            ox = min(lx + lw, bx + bw) - max(lx, bx)
            oy = min(ly + lh, by + bh) - max(ly, by)
            if ox > 2 and oy > 2:
                bad.append(f"{path}: [라벨이 상자를 덮음] 라벨 x={lx:.0f}~{lx+lw:.0f} 이 상자 x={bx:.0f}~{bx+bw:.0f} 와 {ox:.0f}px 겹침")
    return bad


def check(path):
    s = open(path).read()
    rects = [(float(x), float(y), float(w), float(h)) for x, y, w, h in
             re.findall(r'<rect x="([0-9.-]+)" y="([0-9.-]+)" width="([0-9.]+)" height="([0-9.]+)"', s)]
    bad = []
    for m in re.finditer(
            r'<text x="([0-9.-]+)" y="([0-9.-]+)" font-size="([0-9.]+)"[^>]*?'
            r'text-anchor="(\w+)"([^>]*)>([^<]*)</text>', s):
        x, y, size, anchor, rest, text = (float(m.group(1)), float(m.group(2)),
                                          float(m.group(3)), m.group(4), m.group(5), m.group(6))
        if not text.strip():
            continue
        w = approx(text, size, "monospace" in rest)
        left = x - w / 2 if anchor == "middle" else (x - w if anchor == "end" else x)
        right = left + w
        if left < 2 or right > W - 2:
            bad.append((text[:44], "화면 밖", round(left), round(right)))
            continue
        # 이 글자를 담고 있는 가장 작은 상자를 찾는다
        host = None
        for rx, ry, rw, rh in rects:
            if rw >= W - 10:
                continue
            if rx <= x <= rx + rw and ry - 4 <= y <= ry + rh + 4:
                if host is None or rw < host[2]:
                    host = (rx, ry, rw, rh)
        if host and (left < host[0] + 1 or right > host[0] + host[2] - 1):
            bad.append((text[:44], "상자 넘침", round(left), round(right)))
    return bad


def balance(path):
    """내용이 가로로 치우쳐 있는지 본다. 좌우 여백 차이가 크면 한쪽이 비어 보인다."""
    s = open(path).read()
    lo, hi = W, 0
    for m in re.finditer(r'<rect x="([0-9.-]+)" y="[0-9.-]+" width="([0-9.]+)"', s):
        x, w = float(m.group(1)), float(m.group(2))
        if w >= W - 10:      # 바탕 사각형은 뺀다
            continue
        lo, hi = min(lo, x), max(hi, x + w)
    for m in re.finditer(r'<text x="([0-9.-]+)" y="[0-9.-]+" font-size="([0-9.]+)"[^>]*?'
                         r'text-anchor="(\w+)"([^>]*)>([^<]*)</text>', s):
        x, size, anchor, rest, text = (float(m.group(1)), float(m.group(2)), m.group(3),
                                       m.group(4), m.group(5))
        if not text.strip():
            continue
        w = approx(text, size, "monospace" in rest)
        left = x - w / 2 if anchor == "middle" else (x - w if anchor == "end" else x)
        lo, hi = min(lo, left), max(hi, left + w)
    for m in re.finditer(r'<svg x="([0-9.-]+)"[^>]*?width="([0-9.]+)"', s):
        x, w = float(m.group(1)), float(m.group(2))
        lo, hi = min(lo, x), max(hi, x + w)
    return round(lo), round(W - hi)


if __name__ == "__main__":
    files = sys.argv[1:] or sorted(glob.glob("figures/[a-z]*.svg"))
    total = 0
    for f in files:
        for text, kind, l, r in check(f):
            print(f"{f}: [{kind}] {l}~{r}  '{text}'")
            total += 1
        lm, rm = balance(f)
        if abs(lm - rm) > 24:
            print(f"{f}: [가로 치우침] 왼쪽 여백 {lm}, 오른쪽 여백 {rm}")
            total += 1
    print(f"검출 {total}건" if total else "검출 0건")
    sys.exit(1 if total else 0)
