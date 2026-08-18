#!/usr/bin/env python3
"""이중 방언 MCP 부하 하네스 (파일럿).

MCP 전용 부하 도구가 세상에 없어서 자작 (2026-07-07 조사에서 공백 확인).
SDK를 쓰지 않고 raw HTTP로 두 방언을 직접 구사한다. 프로토콜 수준 오류(404/400,
세션 유실, handle 오류)를 계수해야 하기 때문.

A 방언 (2025-11-25, 세션):
  initialize -> Mcp-Session-Id 헤더 수신 -> notifications/initialized -> tools/call 루프.
  404(스펙 규범) 또는 400(everything 서버 실제 동작) 수신 시 세션 유실로 계수하고 재초기화.

B 방언 (2026-07-28 RC, stateless):
  핸드셰이크 없음. 매 요청에 MCP-Protocol-Version / Mcp-Method / Mcp-Name 헤더와
  params._meta(protocolVersion, clientInfo, clientCapabilities).

워크로드:
  echo          : stateless 도구 호출 (A/B 공통)
  counter_mem   : B 전용. in-memory handle (naive 포팅 병리 관찰)
  counter_hmac  : B 전용. self-contained handle (어느 replica든 처리 가능)

닫힌 루프(worker N개가 응답 받는 대로 다음 요청). offered ~= achieved.
--conn-mode close 는 요청마다 새 TCP 연결 (kube-proxy가 연결 단위 밸런싱이라
per-request 분산을 보려면 필수. reuse는 keep-alive로 파드 고정 관찰용).

출력: JSON (stdout 요약 + --out 파일).
"""

import argparse
import asyncio
import json
import sys
import time
from collections import Counter

import httpx

PROTO_A = "2025-11-25"
PROTO_B = "2026-07-28"


def pctl(sorted_vals, p):
    if not sorted_vals:
        return None
    k = max(0, min(len(sorted_vals) - 1, int(round(p / 100 * (len(sorted_vals) - 1)))))
    return sorted_vals[k]


def parse_body(resp):
    """application/json 또는 SSE(text/event-stream) 응답에서 JSON-RPC 응답 객체 추출."""
    ctype = resp.headers.get("content-type", "")
    text = resp.text
    if ctype.startswith("text/event-stream"):
        last = None
        for line in text.splitlines():
            if line.startswith("data:"):
                try:
                    obj = json.loads(line[5:].strip())
                except json.JSONDecodeError:
                    continue
                if isinstance(obj, dict) and ("result" in obj or "error" in obj):
                    last = obj
        return last
    if ctype.startswith("application/json") and text:
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            return None
    return None


class Stats:
    def __init__(self):
        self.ok = 0
        self.latencies = []  # seconds, successful tools/call only
        self.errors = Counter()
        self.session_loss = 0  # A: 404/400 on established session
        # 5xx는 세션 유실과 성격이 다르다. 게이트웨이 경유에서 failureMode가
        # FailClosed면 대상 파드가 사라졌을 때 세션 전체를 5xx로 실패시키는데,
        # 이걸 세션 유실로 세면 "유실 0"이라는 착시가 생긴다 (2026-08-10 추가).
        self.gateway_error = 0  # 5xx
        self.other_fail = 0  # 그 밖의 non-200
        self.reinit = 0  # A: re-initialize count
        self.handle_loss = 0  # B: unknown-handle tool errors
        self.pods = Counter()  # echo 응답에 파드 식별이 없어 counter_mem 오류로만 관찰
        self.reconnects = 0  # 새 TCP 연결 수립 횟수 (keep-alive 유실 상관 정량화)
        self.offered = 0  # 열린 루프: 스케줄된 요청 수
        self.shed = 0  # 열린 루프: 클라이언트 포화로 버려진 틱


_ACTIVE_STATS = None  # connect_tcp 몽키패치가 참조


def _install_reconnect_counter():
    """httpcore의 TCP 연결 수립을 계수한다 (하네스 전용 몽키패치)."""
    import httpcore._backends.anyio as _anyio

    orig = _anyio.AnyIOBackend.connect_tcp

    async def counting(self, *a, **k):
        if _ACTIVE_STATS is not None:
            _ACTIVE_STATS.reconnects += 1
        return await orig(self, *a, **k)

    _anyio.AnyIOBackend.connect_tcp = counting


class WorkerA:
    """2025-11-25 세션 방언."""

    def __init__(self, client, url, stats, tool, rid_base):
        self.client, self.url, self.stats = client, url, stats
        self.tool = tool
        self.rid = rid_base
        self.session = None

    def _headers(self, with_session=True):
        h = {
            "Accept": "application/json, text/event-stream",
            "Content-Type": "application/json",
        }
        if with_session and self.session:
            h["Mcp-Session-Id"] = self.session
        return h

    async def initialize(self):
        self.rid += 1
        r = await self.client.post(
            self.url,
            headers=self._headers(with_session=False),
            json={
                "jsonrpc": "2.0",
                "id": self.rid,
                "method": "initialize",
                "params": {
                    "protocolVersion": PROTO_A,
                    "capabilities": {},
                    "clientInfo": {"name": "loadgen", "version": "0.1"},
                },
            },
        )
        r.raise_for_status()
        # 구 스펙에서 세션은 서버 재량(MAY). 없으면 세션리스로 진행한다
        # (v2 SDK의 legacy 모드가 이 경우: initialize에 응답하되 세션 미발급).
        self.session = r.headers.get("mcp-session-id")
        # notifications/initialized
        await self.client.post(
            self.url,
            headers=self._headers(),
            json={"jsonrpc": "2.0", "method": "notifications/initialized"},
        )

    async def call_once(self):
        self.rid += 1
        args = {"message": "ping"} if self.tool == "echo" else {"a": 1, "b": 2}
        t0 = time.perf_counter()
        try:
            r = await self.client.post(
                self.url,
                headers=self._headers(),
                json={
                    "jsonrpc": "2.0",
                    "id": self.rid,
                    "method": "tools/call",
                    "params": {"name": self.tool, "arguments": args},
                },
            )
        except httpx.HTTPError as e:
            self.stats.errors[f"conn:{type(e).__name__}"] += 1
            return
        dt = time.perf_counter() - t0
        # 세션을 잃었을 때 어떤 코드가 오는지는 경로마다 다르다. 직접 경로는
        # 400/404(스펙은 404, everything 서버는 400)이고, 게이트웨이 경유는
        # failureMode가 세션 전체를 실패시키면서 5xx로 온다. 둘 다 재초기화로
        # 복구해야 경로 사이 비교가 성립한다. 5xx에서 복구하지 않으면 그 워커가
        # 남은 실행 내내 실패해서, 게이트웨이가 훨씬 나빠 보이는 착시가 생긴다
        # (2026-08-10, V1에서 발견. 그 전 게이트웨이 수치는 이 결함의 영향을 받음).
        if r.status_code in (404, 400) or 500 <= r.status_code < 600:
            if r.status_code in (404, 400):
                self.stats.session_loss += 1
            else:
                self.stats.gateway_error += 1
            self.stats.errors[f"http:{r.status_code}"] += 1
            try:
                await self.initialize()
                self.stats.reinit += 1
            except Exception as e:
                self.stats.errors[f"reinit:{type(e).__name__}"] += 1
                await asyncio.sleep(0.2)
            return
        if r.status_code != 200:
            self.stats.errors[f"http:{r.status_code}"] += 1
            self.stats.other_fail += 1
            return
        obj = parse_body(r)
        if obj is None:
            self.stats.errors["parse"] += 1
        elif "error" in obj:
            self.stats.errors[f"rpc:{obj['error'].get('code')}"] += 1
        elif obj.get("result", {}).get("isError"):
            self.stats.errors["tool"] += 1
        else:
            self.stats.ok += 1
            self.stats.latencies.append(dt)


class WorkerB:
    """2026-07-28 stateless 방언."""

    META = {
        "io.modelcontextprotocol/protocolVersion": PROTO_B,
        "io.modelcontextprotocol/clientInfo": {"name": "loadgen", "version": "0.1"},
        "io.modelcontextprotocol/clientCapabilities": {},
    }

    def __init__(self, client, url, stats, tool, rid_base):
        self.client, self.url, self.stats = client, url, stats
        self.tool = tool
        self.rid = rid_base
        self.handle = None

    def _headers(self, method, name=None):
        h = {
            "Accept": "application/json, text/event-stream",
            "Content-Type": "application/json",
            "MCP-Protocol-Version": PROTO_B,
            "Mcp-Method": method,
        }
        if name:
            h["Mcp-Name"] = name
        return h

    async def _call(self, name, args):
        self.rid += 1
        r = await self.client.post(
            self.url,
            headers=self._headers("tools/call", name),
            json={
                "jsonrpc": "2.0",
                "id": self.rid,
                "method": "tools/call",
                "params": {"name": name, "arguments": args, "_meta": self.META},
            },
        )
        return r

    async def _create_handle(self, name):
        """handle 생성. 연결 오류는 계수하고 None 반환 (전체 실행을 죽이지 않는다)."""
        try:
            r = await self._call(name, {})
        except httpx.HTTPError as e:
            self.stats.errors[f"conn:{type(e).__name__}"] += 1
            return None
        obj = parse_body(r) if r.status_code == 200 else None
        if obj and "error" not in obj and not obj.get("result", {}).get("isError"):
            return self._text_result(obj)
        self.stats.errors["create_failed"] += 1
        return None

    @staticmethod
    def _text_result(obj):
        content = obj.get("result", {}).get("content", [])
        for c in content:
            if c.get("type") == "text":
                return c.get("text", "")
        return ""

    async def call_once(self):
        # 워크로드 결정
        if self.tool == "echo":
            name, args = "echo", {"message": "ping"}
        elif self.tool == "counter_mem":
            if self.handle is None:
                self.handle = await self._create_handle("counter_create")
                if self.handle is None:
                    return
            name, args = "counter_incr", {"handle": self.handle}
        elif self.tool == "counter_hmac":
            if self.handle is None:
                self.handle = await self._create_handle("hcounter_create")
                if self.handle is None:
                    return
            name, args = "hcounter_incr", {"handle": self.handle}
        elif self.tool == "counter_redis":
            if self.handle is None:
                self.handle = await self._create_handle("rcounter_create")
                if self.handle is None:
                    return
            name, args = "rcounter_incr", {"handle": self.handle}
        else:
            raise ValueError(self.tool)

        t0 = time.perf_counter()
        try:
            r = await self._call(name, args)
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
        obj = parse_body(r)
        if obj is None:
            self.stats.errors["parse"] += 1
        elif "error" in obj:
            self.stats.errors[f"rpc:{obj['error'].get('code')}"] += 1
        elif obj.get("result", {}).get("isError"):
            text = self._text_result(obj)
            if "unknown handle" in text:
                self.stats.handle_loss += 1
                # 파드 식별 기록 (오류 메시지에 pod= 포함)
                if "pod=" in text:
                    self.stats.pods[text.split("pod=")[1].rstrip(")")] += 1
                self.handle = None  # 재생성
            else:
                self.stats.errors["tool"] += 1
        else:
            self.stats.ok += 1
            self.stats.latencies.append(dt)
            if name == "hcounter_incr":
                self.handle = self._text_result(obj)  # self-contained: 새 handle 갱신


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
        workers = []
        for i in range(args.concurrency):
            cls = WorkerA if args.dialect == "a" else WorkerB
            workers.append(cls(client, args.url, stats, args.tool, rid_base=i * 1_000_000))
        if args.dialect == "a":
            for w in workers:
                await w.initialize()

        deadline = time.monotonic() + args.duration
        t_start = time.time()

        if args.rps > 0:
            # 열린 루프: 고정 rps로 틱 발행, 워커가 큐에서 소비.
            # 큐가 차면 shed 계수 = 클라이언트/서버가 목표 부하를 못 따라감 (포화 신호).
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
                    await queue.put(None)  # 종료 신호

            async def consume(w):
                while True:
                    tok = await queue.get()
                    if tok is None:
                        return
                    await w.call_once()

            await asyncio.gather(scheduler(), *(consume(w) for w in workers))
        else:
            # 닫힌 루프 (기본): 워커가 응답 즉시 다음 요청
            async def loop(w):
                while time.monotonic() < deadline:
                    await w.call_once()

            await asyncio.gather(*(loop(w) for w in workers))
        elapsed = time.time() - t_start

    lat = sorted(stats.latencies)
    out = {
        "config": vars(args),
        "elapsed_s": round(elapsed, 2),
        "ok": stats.ok,
        "achieved_rps": round(stats.ok / elapsed, 1) if elapsed else 0,
        "latency_ms": {
            "p50": round(pctl(lat, 50) * 1000, 1) if lat else None,
            "p95": round(pctl(lat, 95) * 1000, 1) if lat else None,
            "p99": round(pctl(lat, 99) * 1000, 1) if lat else None,
        },
        "session_loss": stats.session_loss,
        "gateway_error": stats.gateway_error,
        "other_fail": stats.other_fail,
        "reinit": stats.reinit,
        "handle_loss": stats.handle_loss,
        "handle_loss_pods": dict(stats.pods),
        "errors": dict(stats.errors),
        "reconnects": stats.reconnects,
        "offered": stats.offered if args.rps > 0 else None,
        "shed": stats.shed if args.rps > 0 else None,
    }
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--url", required=True, help="MCP endpoint, e.g. http://192.168.2.230/mcp")
    p.add_argument("--dialect", choices=["a", "b"], required=True)
    p.add_argument("--tool", default="echo", choices=["echo", "get-sum", "counter_mem", "counter_hmac", "counter_redis"])
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
