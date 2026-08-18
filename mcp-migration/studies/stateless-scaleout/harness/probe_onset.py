#!/usr/bin/env python3
"""세션이 몇 번째 새 연결에서 깨지는지 분포를 잰다 (2026-08-08 추가).

capture.py 는 첫 실패 하나만 기록해서 "몇 번째에서 깨졌다"를 한 번밖에 못 본다.
발행문에 분포로 쓰려면 반복이 필요하다. 여기서는 세션을 새로 만든 뒤 새 연결로
호출을 반복해 몇 번째에서 400이 나오는지를 시행마다 기록한다.

레플리카가 N개면 연결마다 세션 파드에 닿을 확률이 1/N이므로 첫 실패까지의
시행 횟수는 기하분포를 따르고 기댓값은 N/(N-1)이다. 실측이 이 값과 맞는지
보는 것이 목적이다.

사용: python3 harness/probe_onset.py <A_URL> <TRIALS> <OUT_JSON>
  예: python3 harness/probe_onset.py http://192.168.2.230/mcp 60 runs/onset-r2.json
"""

import json
import statistics
import subprocess
import sys

import httpx

PROTO_A = "2025-11-25"
BASE = {"Accept": "application/json, text/event-stream", "Content-Type": "application/json"}
MAX_TRIES = 60  # 이 안에 안 깨지면 그 시행은 우측 절단으로 기록한다


def replicas():
    try:
        out = subprocess.run(
            ["kubectl", "--context", "mcp-migration", "-n", "mcp-pilot", "get", "deploy",
             "mcp-a", "-o", "jsonpath={.status.readyReplicas}"],
            capture_output=True, text=True, timeout=20, check=True).stdout.strip()
        return int(out or 0)
    except Exception:
        return 0


def new_session(url):
    """새 연결에서 핸드셰이크를 마치고 세션 ID를 받는다."""
    with httpx.Client(timeout=20) as c:
        r = c.post(url, headers=BASE, json={
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {"protocolVersion": PROTO_A, "capabilities": {},
                       "clientInfo": {"name": "onset", "version": "0.1"}},
        })
        r.raise_for_status()
        sid = r.headers.get("mcp-session-id")
        if not sid:
            raise RuntimeError("세션 미발급")
        h = dict(BASE, **{"Mcp-Session-Id": sid})
        c.post(url, headers=h, json={"jsonrpc": "2.0", "method": "notifications/initialized"})
        return h


def tries_until_loss(url, headers):
    """새 연결로 호출을 반복해 몇 번째에서 세션이 깨지는지 센다.

    연결마다 클라이언트를 새로 만들어야 kube-proxy가 다시 분배한다.
    """
    for i in range(1, MAX_TRIES + 1):
        with httpx.Client(timeout=20) as c:
            r = c.post(url, headers=headers, json={
                "jsonrpc": "2.0", "id": 100 + i, "method": "tools/call",
                "params": {"name": "echo", "arguments": {"message": "ping"}},
            })
        if r.status_code in (400, 404):
            return i
    return None  # 우측 절단


if __name__ == "__main__":
    url, trials, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    n = replicas()
    print(f"mcp-a 레플리카 {n}개, {trials}회 시행")

    results, censored = [], 0
    for t in range(trials):
        try:
            headers = new_session(url)
        except Exception as e:
            print(f"  [{t + 1}] 세션 생성 실패: {e}")
            continue
        k = tries_until_loss(url, headers)
        if k is None:
            censored += 1
            print(f"  [{t + 1}] {MAX_TRIES}회 안에 안 깨짐 (절단)")
        else:
            results.append(k)
            if (t + 1) % 10 == 0:
                print(f"  [{t + 1}] 진행 중, 지금까지 중앙값 {statistics.median(results)}")

    doc = {
        "replicas": n, "trials": trials, "censored": censored,
        "tries_until_loss": results,
        "mean": statistics.mean(results) if results else None,
        "median": statistics.median(results) if results else None,
        "expected_geometric": n / (n - 1) if n > 1 else None,
        "first_try_share": sum(1 for k in results if k == 1) / len(results) if results else None,
    }
    open(out, "w").write(json.dumps(doc, indent=2))
    if results:
        print(f"\n첫 실패까지 시행: 평균 {doc['mean']:.2f}, 중앙값 {doc['median']}, "
              f"기하분포 기댓값 {doc['expected_geometric']:.2f}")
        print(f"첫 연결에서 바로 깨진 비율: {doc['first_try_share'] * 100:.0f}%")
    print(f"저장: {out}")
