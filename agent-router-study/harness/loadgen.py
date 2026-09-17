#!/usr/bin/env python3
"""오버헤드 측정. 같은 도구 호출을 동시에 여러 개 보내고 지연 분포를 낸다.

게이트웨이를 거친 경로와 백엔드를 직접 부른 경로를 같은 방식으로 재야 비교가 된다.
세션은 워커마다 따로 연다. MCP가 세션을 요구하므로 공유하면 직렬화된다.
"""
import argparse, json, os, statistics, threading, time
import httpx


def sse_json(text):
    for line in text.splitlines():
        if line.startswith("data: "):
            try:
                return json.loads(line[6:])
            except json.JSONDecodeError:
                return None
    return None


class Worker(threading.Thread):
    def __init__(self, url, tool, args, dur, stop):
        super().__init__(daemon=True)
        self.url, self.tool, self.args, self.dur, self.stop = url, tool, args, dur, stop
        self.samples, self.ok, self.err = [], 0, 0
        self.codes = {}

    def run(self):
        c = httpx.Client(timeout=30.0)
        h = {"Content-Type": "application/json",
             "Accept": "application/json, text/event-stream"}
        r = c.post(self.url, headers=h, content=json.dumps(
            {"jsonrpc": "2.0", "id": 1, "method": "initialize",
             "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                        "clientInfo": {"name": "load", "version": "1"}}}))
        sid = r.headers.get("mcp-session-id")
        if sid:
            h["Mcp-Session-Id"] = sid
        c.post(self.url, headers=h, content=json.dumps(
            {"jsonrpc": "2.0", "method": "notifications/initialized"}))
        body = json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
                           "params": {"name": self.tool, "arguments": self.args}})
        end = time.time() + self.dur
        while time.time() < end and not self.stop.is_set():
            t0 = time.perf_counter()
            try:
                rr = c.post(self.url, headers=h, content=body)
                self.samples.append((time.perf_counter() - t0) * 1000)
                self.codes[rr.status_code] = self.codes.get(rr.status_code, 0) + 1
                j = sse_json(rr.text)
                if rr.status_code == 200 and j and "result" in j:
                    self.ok += 1
                else:
                    self.err += 1
            except Exception:
                self.err += 1
        c.close()


def pct(xs, p):
    if not xs:
        return None
    xs = sorted(xs)
    i = min(len(xs) - 1, int(round(p / 100 * (len(xs) - 1))))
    return round(xs[i], 3)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--tool", default="mcpb__get-sum")
    ap.add_argument("--conc", type=int, default=8)
    ap.add_argument("--dur", type=int, default=30)
    ap.add_argument("--label", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    stop = threading.Event()
    ws = [Worker(a.url, a.tool, {"a": 1, "b": 2}, a.dur, stop) for _ in range(a.conc)]
    t0 = time.time()
    for w in ws:
        w.start()
    for w in ws:
        w.join(a.dur + 40)
    elapsed = time.time() - t0

    samples = [s for w in ws for s in w.samples]
    codes = {}
    for w in ws:
        for k, v in w.codes.items():
            codes[k] = codes.get(k, 0) + v
    res = {"label": a.label, "url": a.url, "tool": a.tool, "conc": a.conc,
           "dur": a.dur, "elapsed": round(elapsed, 2),
           "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
           "n": len(samples), "ok": sum(w.ok for w in ws), "err": sum(w.err for w in ws),
           "codes": {str(k): v for k, v in codes.items()},
           "rps": round(len(samples) / elapsed, 2) if elapsed else None,
           "p50": pct(samples, 50), "p95": pct(samples, 95), "p99": pct(samples, 99),
           "min": round(min(samples), 3) if samples else None,
           "mean": round(statistics.mean(samples), 3) if samples else None}
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    json.dump(res, open(a.out, "w"), ensure_ascii=False, indent=2)
    print(f"[{a.label}] conc={a.conc} n={res['n']} rps={res['rps']} "
          f"p50={res['p50']} p95={res['p95']} err={res['err']}")


if __name__ == "__main__":
    main()
