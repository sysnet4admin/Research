#!/usr/bin/env python3
"""목표 rps를 고정해 재는 부하 측정기. agentgateway-study가 쓴 방식과 같은 잣대다.

동시성을 열어 놓고 쓸면 포화 지점만 보이고 "같은 부하에서 얼마를 더 쓰는가"를
못 낸다. 그래서 보낼 시각을 미리 정해 두고 그 일정대로 던진다. 일정 시각에 빈
워커가 없으면 그 요청은 보내지 못한 것으로 세고(shed) 달성 rps와 함께 적는다.

연결 모드가 둘이다. reuse는 keep-alive를 유지하고 close는 요청마다 연결을 새로
연다. MCP 프록시가 백엔드로 나갈 때 Go 기본 전송을 그대로 써서 호스트당 유휴
연결을 2개만 두므로 이 구분이 결과를 나눌 수 있다.
"""
import argparse, json, os, queue, statistics, threading, time
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
    def __init__(self, url, tool, mode, q, res, lock):
        super().__init__(daemon=True)
        self.url, self.tool, self.mode = url, tool, mode
        self.q, self.res, self.lock = q, res, lock
        self.c = httpx.Client(timeout=30.0)
        self.h = {"Content-Type": "application/json",
                  "Accept": "application/json, text/event-stream"}
        self.ready = threading.Event()

    def open_session(self):
        r = self.c.post(self.url, headers=self.h, content=json.dumps(
            {"jsonrpc": "2.0", "id": 1, "method": "initialize",
             "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                        "clientInfo": {"name": "rate", "version": "1"}}}))
        sid = r.headers.get("mcp-session-id")
        if sid:
            self.h["Mcp-Session-Id"] = sid
        self.c.post(self.url, headers=self.h, content=json.dumps(
            {"jsonrpc": "2.0", "method": "notifications/initialized"}))
        self.ready.set()

    def run(self):
        try:
            self.open_session()
        except Exception as e:
            self.res["init_err"] = str(e)[:120]
            self.ready.set()
            return
        body = json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
                           "params": {"name": self.tool, "arguments": {"a": 1, "b": 2}}})
        h = dict(self.h)
        if self.mode == "close":
            h["Connection"] = "close"
        while True:
            item = self.q.get()
            if item is None:
                break
            t0 = time.perf_counter()
            try:
                r = self.c.post(self.url, headers=h, content=body)
                ms = (time.perf_counter() - t0) * 1000
                j = sse_json(r.text)
                ok = r.status_code == 200 and j is not None and "result" in j
                with self.lock:
                    self.res["samples"].append(ms)
                    self.res["codes"][r.status_code] = self.res["codes"].get(r.status_code, 0) + 1
                    if ok:
                        self.res["ok"] += 1
                    else:
                        self.res["err"] += 1
            except Exception:
                with self.lock:
                    self.res["err"] += 1
        self.c.close()


def pct(xs, p):
    if not xs:
        return None
    xs = sorted(xs)
    return round(xs[min(len(xs) - 1, int(round(p / 100 * (len(xs) - 1))))], 3)


def run(url, tool, rate, dur, conc, mode):
    q = queue.Queue(maxsize=conc)
    lock = threading.Lock()
    res = {"samples": [], "codes": {}, "ok": 0, "err": 0}
    ws = [Worker(url, tool, mode, q, res, lock) for _ in range(conc)]
    for w in ws:
        w.start()
    for w in ws:
        w.ready.wait(30)

    total = int(rate * dur)
    interval = 1.0 / rate
    start = time.perf_counter()
    shed = 0
    for i in range(total):
        due = start + i * interval
        now = time.perf_counter()
        if due > now:
            time.sleep(due - now)
        try:
            q.put_nowait(i)
        except queue.Full:
            shed += 1
    elapsed = time.perf_counter() - start
    for _ in ws:
        q.put(None)
    for w in ws:
        w.join(60)

    s = res["samples"]
    return {"rate_target": rate, "dur": dur, "conc": conc, "mode": mode,
            "url": url, "tool": tool, "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "elapsed": round(elapsed, 2), "issued": total - shed, "shed": shed,
            "n": len(s), "ok": res["ok"], "err": res["err"],
            "codes": {str(k): v for k, v in res["codes"].items()},
            "init_err": res.get("init_err"),
            "rate_achieved": round(len(s) / elapsed, 2) if elapsed else None,
            "p50": pct(s, 50), "p95": pct(s, 95), "p99": pct(s, 99),
            "min": round(min(s), 3) if s else None,
            "mean": round(statistics.mean(s), 3) if s else None}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--tool", default="mcpb__get-sum")
    ap.add_argument("--rate", type=float, required=True)
    ap.add_argument("--dur", type=int, default=30)
    ap.add_argument("--conc", type=int, default=8)
    ap.add_argument("--mode", choices=["close", "reuse"], default="close")
    ap.add_argument("--label", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    r = run(a.url, a.tool, a.rate, a.dur, a.conc, a.mode)
    r["label"] = a.label
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    json.dump(r, open(a.out, "w"), ensure_ascii=False, indent=2)
    print(f"[{a.label}] 목표={a.rate} 달성={r['rate_achieved']} mode={a.mode} "
          f"p50={r['p50']} p99={r['p99']} shed={r['shed']} 오류={r['err']}")
