#!/usr/bin/env python3
"""A2A message/send 부하 하네스.

mcp-migration의 loadgen.py(이중 방언 MCP 하네스) 구조를 A2A 방언으로 이식한
별도 파일이다. 원본은 발행된 측정의 자산이라 수정하지 않는다(드리프트 방지).
공유하는 뼈대: 닫힌/열린 루프, --conn-mode(close = 요청마다 새 TCP), 재연결
계수 몽키패치, JSON 출력(achieved_rps, p50/p95/p99, 오류 분류).

A2A 방언: JSON-RPC POST message/send, 성공 판정 = HTTP 200이고 result.kind가
message. JSON-RPC error는 rpc:<code>로 계수.
"""

import argparse
import asyncio
import json
import time
from collections import Counter

import httpx


def pctl(sorted_vals, p):
    if not sorted_vals:
        return None
    k = max(0, min(len(sorted_vals) - 1, int(round(p / 100 * (len(sorted_vals) - 1)))))
    return sorted_vals[k]


class Stats:
    def __init__(self):
        self.ok = 0
        self.latencies = []
        self.errors = Counter()
        self.gateway_error = 0  # 5xx
        self.other_fail = 0     # 그 밖의 non-200
        self.reconnects = 0
        self.offered = 0
        self.shed = 0


_ACTIVE_STATS = None


def _install_reconnect_counter():
    """httpcore의 TCP 연결 수립을 계수한다 (하네스 전용 몽키패치)."""
    import httpcore._backends.anyio as _anyio

    orig = _anyio.AnyIOBackend.connect_tcp

    async def counting(self, *a, **k):
        if _ACTIVE_STATS is not None:
            _ACTIVE_STATS.reconnects += 1
        return await orig(self, *a, **k)

    _anyio.AnyIOBackend.connect_tcp = counting


class Worker:
    def __init__(self, client, url, stats, rid_base):
        self.client, self.url, self.stats = client, url, stats
        self.rid = rid_base

    async def call_once(self):
        self.rid += 1
        t0 = time.perf_counter()
        try:
            r = await self.client.post(
                self.url,
                headers={"Content-Type": "application/json"},
                json={
                    "jsonrpc": "2.0",
                    "id": self.rid,
                    "method": "message/send",
                    "params": {"message": {
                        "kind": "message", "role": "user",
                        "messageId": f"m-{self.rid}",
                        "parts": [{"kind": "text", "text": "ping"}]}},
                },
            )
        except httpx.HTTPError as e:
            self.stats.errors[f"conn:{type(e).__name__}"] += 1
            return
        dt = time.perf_counter() - t0
        if r.status_code != 200:
            self.stats.errors[f"http:{r.status_code}"] += 1
            if 500 <= r.status_code < 600:
                self.stats.gateway_error += 1
            else:
                self.stats.other_fail += 1
            return
        try:
            obj = r.json()
        except json.JSONDecodeError:
            self.stats.errors["parse"] += 1
            return
        if "error" in obj:
            self.stats.errors[f"rpc:{obj['error'].get('code')}"] += 1
        elif obj.get("result", {}).get("kind") == "message":
            self.stats.ok += 1
            self.stats.latencies.append(dt)
        else:
            self.stats.errors["shape"] += 1


async def run(args):
    global _ACTIVE_STATS
    stats = Stats()
    _ACTIVE_STATS = stats
    _install_reconnect_counter()
    limits = httpx.Limits(
        max_connections=args.concurrency * 2,
        max_keepalive_connections=0 if args.conn_mode == "close" else args.concurrency * 2,
    )
    headers = {"Connection": "close"} if args.conn_mode == "close" else {}
    async with httpx.AsyncClient(timeout=10.0, limits=limits, headers=headers) as client:
        workers = [Worker(client, args.url, stats, rid_base=i * 1_000_000)
                   for i in range(args.concurrency)]
        deadline = time.monotonic() + args.duration
        t_start = time.time()

        if args.rps > 0:
            # 열린 루프: 고정 rps 틱, 큐가 차면 shed 계수 (생성기/서버 포화 신호)
            queue = asyncio.Queue(maxsize=max(args.concurrency * 2, 16))

            async def scheduler():
                interval = 1.0 / args.rps
                next_t = time.monotonic()
                while next_t < deadline:
                    now = time.monotonic()
                    if now < next_t:
                        await asyncio.sleep(next_t - now)
                    stats.offered += 1
                    try:
                        queue.put_nowait(1)
                    except asyncio.QueueFull:
                        stats.shed += 1
                    next_t += interval
                for _ in workers:
                    await queue.put(None)

            async def consume(w):
                while True:
                    tok = await queue.get()
                    if tok is None:
                        return
                    await w.call_once()

            await asyncio.gather(scheduler(), *(consume(w) for w in workers))
        else:
            async def loop(w):
                while time.monotonic() < deadline:
                    await w.call_once()

            await asyncio.gather(*(loop(w) for w in workers))
        elapsed = time.time() - t_start

    lat = sorted(stats.latencies)
    return {
        "config": vars(args),
        "elapsed_s": round(elapsed, 2),
        "ok": stats.ok,
        "achieved_rps": round(stats.ok / elapsed, 1) if elapsed else 0,
        "latency_ms": {
            "p50": round(pctl(lat, 50) * 1000, 1) if lat else None,
            "p95": round(pctl(lat, 95) * 1000, 1) if lat else None,
            "p99": round(pctl(lat, 99) * 1000, 1) if lat else None,
        },
        "gateway_error": stats.gateway_error,
        "other_fail": stats.other_fail,
        "errors": dict(stats.errors),
        "reconnects": stats.reconnects,
        "offered": stats.offered if args.rps > 0 else None,
        "shed": stats.shed if args.rps > 0 else None,
    }


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--url", required=True, help="A2A endpoint, e.g. http://192.168.2.232/agent")
    p.add_argument("--concurrency", type=int, default=8)
    p.add_argument("--duration", type=int, default=30, help="seconds")
    p.add_argument("--conn-mode", choices=["reuse", "close"], default="close")
    p.add_argument("--rps", type=int, default=0, help="열린 루프 목표 rps (0=닫힌 루프)")
    p.add_argument("--out", help="JSON 결과 파일 경로")
    args = p.parse_args()

    out = asyncio.run(run(args))
    print(json.dumps(out, indent=2, ensure_ascii=False))
    if args.out:
        with open(args.out, "w") as f:
            json.dump(out, f, indent=2, ensure_ascii=False)


if __name__ == "__main__":
    main()
