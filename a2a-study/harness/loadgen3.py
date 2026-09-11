#!/usr/bin/env python3
"""세 구현 부하 생성기 (a2a-study 축 3).

agentgateway-study/a2a/harness/loadgen_a2a.py의 최소 델타 사본이다. 스케줄러(열린
루프, shed 계수), 연결 모드, 재연결 계수 몽키패치, 통계와 JSON 출력은 그대로 두고
요청 구성과 성공 판정만 --arm으로 갈랐다. 세 구현의 계측 방식이 같아야 구현 사이 비교가
서므로 한 파일에 둔다.

- http: JSON-RPC POST {"method":"do-work","params":{"text":...}}. 성공 = result.text.
- mcp:  tools/call do-work(신 스펙 _meta 3종, Mcp-Method/Mcp-Name 헤더). 성공 =
        result.content[0].text. 응답이 SSE면 data 줄을 파싱한다.
- a2a:  message/send(v0.3 형식). 성공 = result.kind가 task이고 status.state가
        completed, 또는 result.kind가 message.
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
        self.resp_bytes = 0


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


META = {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientInfo": {"name": "loadgen3", "version": "0.1"},
    "io.modelcontextprotocol/clientCapabilities": {},
}


class Worker:
    def __init__(self, client, url, stats, rid_base, arm, text):
        self.client, self.url, self.stats = client, url, stats
        self.rid = rid_base
        self.arm, self.text = arm, text

    def _request(self):
        if self.arm == "http":
            return {}, {"jsonrpc": "2.0", "id": self.rid, "method": "do-work",
                        "params": {"text": self.text}}
        if self.arm == "mcp":
            return ({"Accept": "application/json, text/event-stream",
                     "MCP-Protocol-Version": "2026-07-28",
                     "Mcp-Method": "tools/call", "Mcp-Name": "do-work"},
                    {"jsonrpc": "2.0", "id": self.rid, "method": "tools/call",
                     "params": {"name": "do-work", "arguments": {"text": self.text},
                                "_meta": META}})
        return {}, {"jsonrpc": "2.0", "id": self.rid, "method": "message/send",
                    "params": {"message": {
                        "kind": "message", "role": "user",
                        "messageId": f"m-{self.rid}",
                        "parts": [{"kind": "text", "text": self.text}]}}}

    @staticmethod
    def _parse(text):
        """JSON 또는 SSE(data: 줄) 본문에서 JSON-RPC 객체를 꺼낸다."""
        text = text.strip()
        if text.startswith("{"):
            return json.loads(text)
        for line in text.splitlines():
            if line.startswith("data:"):
                return json.loads(line[5:].strip())
        raise json.JSONDecodeError("no json", text, 0)

    def _ok(self, obj):
        r = obj.get("result")
        if not isinstance(r, dict):
            return False
        if self.arm == "http":
            return "text" in r
        if self.arm == "mcp":
            c = r.get("content") or []
            return bool(c) and "text" in c[0] and not r.get("isError", False)
        if r.get("kind") == "task":
            return (r.get("status") or {}).get("state") == "completed"
        return r.get("kind") == "message"

    async def call_once(self):
        self.rid += 1
        headers, body = self._request()
        headers = {"Content-Type": "application/json", **headers}
        t0 = time.perf_counter()
        try:
            r = await self.client.post(self.url, headers=headers, json=body)
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
            obj = self._parse(r.text)
        except (json.JSONDecodeError, ValueError):
            self.stats.errors["parse"] += 1
            return
        if "error" in obj:
            self.stats.errors[f"rpc:{obj['error'].get('code')}"] += 1
        elif self._ok(obj):
            self.stats.ok += 1
            self.stats.latencies.append(dt)
            self.stats.resp_bytes += len(r.content)
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
        workers = [Worker(client, args.url, stats, rid_base=i * 1_000_000, arm=args.arm, text=args.text)
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
        "resp_bytes_total": stats.resp_bytes,
        "offered": stats.offered if args.rps > 0 else None,
        "shed": stats.shed if args.rps > 0 else None,
    }


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--url", required=True, help="구현의 엔드포인트")
    p.add_argument("--arm", choices=["http", "mcp", "a2a"], required=True)
    p.add_argument("--text", default="hello-world")
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
