#!/usr/bin/env python3
"""Agent Router 셀 프로브. 한 셀의 정책 아래에서 같은 배터리를 돌리고 JSON으로 적는다.

기록하는 것은 셋이다. 목록에 무엇이 남는가, 호출이 통과하는가, 거부가 어떤 모양인가.
지연은 같은 배터리를 N회 돌려 p50을 낸다. 바이트는 HTTP 본문 길이다.
"""
import argparse, json, os, statistics, sys, time
import httpx

DEFAULT_PREFIX = "mcpb__"


def sse_json(text):
    """SSE 본문에서 첫 JSON 메시지를 꺼낸다. 평문이면 None."""
    for line in text.splitlines():
        if line.startswith("data: "):
            try:
                return json.loads(line[6:])
            except json.JSONDecodeError:
                return None
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return None


class Session:
    def __init__(self, url, timeout=20.0):
        self.url = url
        self.c = httpx.Client(timeout=timeout)
        self.sid = None
        self.rid = 0

    def post(self, body, extra=None):
        self.rid += 1
        h = {"Content-Type": "application/json",
             "Accept": "application/json, text/event-stream"}
        if self.sid:
            h["Mcp-Session-Id"] = self.sid
        if extra:
            h.update(extra)
        t0 = time.perf_counter()
        r = self.c.post(self.url, headers=h, content=json.dumps(body))
        ms = (time.perf_counter() - t0) * 1000
        return {"code": r.status_code, "ms": ms, "bytes": len(r.content),
                "text": r.text, "json": sse_json(r.text),
                "resp_headers": dict(r.headers)}

    def initialize(self, extra=None):
        res = self.post({"jsonrpc": "2.0", "id": self.rid + 1, "method": "initialize",
                         "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                                    "clientInfo": {"name": "ar-probe", "version": "1"}}}, extra)
        self.sid = res["resp_headers"].get("mcp-session-id")
        self.post({"jsonrpc": "2.0", "method": "notifications/initialized"})
        return res

    def close(self):
        self.c.close()


def verdict(res):
    """거부의 모양을 분류한다. JSON-RPC 오류인가, HTTP 오류인가, 도구 은닉인가."""
    if res["code"] == 200 and res["json"] and "result" in res["json"]:
        r = res["json"]["result"]
        if isinstance(r, dict) and r.get("isError"):
            return "tool-error"
        return "ok"
    if res["json"] and "error" in res["json"]:
        return f"jsonrpc-error:{res['json']['error'].get('code')}"
    return f"http-{res['code']}"


def battery(url, n, prefix=DEFAULT_PREFIX):
    """한 셀의 배터리. 목록 1회 + 호출 3종 x N회.

    prefix는 클라이언트가 부르는 도구 이름의 접두사다. 게이트웨이를 거치면
    `mcpb__get-sum`이고 백엔드를 직접 부르면 접두사가 없다."""
    tool_sum, tool_echo = prefix + "get-sum", prefix + "echo"
    s = Session(url)
    out = {}
    init = s.initialize()
    out["init"] = {k: init[k] for k in ("code", "ms", "bytes")}

    lst = s.post({"jsonrpc": "2.0", "id": 100, "method": "tools/list", "params": {}})
    tools = []
    if lst["json"] and "result" in lst["json"]:
        tools = [t["name"] for t in lst["json"]["result"].get("tools", [])]
    out["list"] = {"code": lst["code"], "ms": lst["ms"], "bytes": lst["bytes"],
                   "tools": tools, "n_tools": len(tools), "verdict": verdict(lst)}

    calls = {
        "sum_a1": {"name": tool_sum, "arguments": {"a": 1, "b": 2}},
        "sum_a2": {"name": tool_sum, "arguments": {"a": 2, "b": 2}},
        "echo": {"name": tool_echo, "arguments": {"message": "hi"}},
    }
    for key, params in calls.items():
        samples, first = [], None
        for _ in range(n):
            r = s.post({"jsonrpc": "2.0", "id": 200, "method": "tools/call", "params": params})
            samples.append(r["ms"])
            if first is None:
                first = r
        out[key] = {"code": first["code"], "bytes": first["bytes"],
                    "verdict": verdict(first), "body": first["text"][:400],
                    "p50_ms": round(statistics.median(samples), 3),
                    "min_ms": round(min(samples), 3), "n": n}
    s.close()
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--cell", required=True)
    ap.add_argument("--n", type=int, default=20)
    ap.add_argument("--out", required=True)
    ap.add_argument("--prefix", default=DEFAULT_PREFIX,
                    help="도구 이름 접두사. 백엔드를 직접 부를 때는 빈 문자열")
    a = ap.parse_args()
    res = {"cell": a.cell, "url": a.url, "n": a.n,
           "prefix": a.prefix, "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
           "probes": battery(a.url, a.n, a.prefix)}
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with open(a.out, "w") as f:
        json.dump(res, f, ensure_ascii=False, indent=2)
    p = res["probes"]
    print(f"[{a.cell}] list={p['list']['n_tools']}개 {p['list']['verdict']}  "
          f"a1={p['sum_a1']['verdict']} {p['sum_a1']['p50_ms']}ms  "
          f"a2={p['sum_a2']['verdict']}  echo={p['echo']['verdict']}")


if __name__ == "__main__":
    main()
