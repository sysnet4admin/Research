#!/usr/bin/env python3
"""축 4. 게이트웨이가 백엔드에 트레이스 컨텍스트를 넘기는지 본다.

클라이언트가 traceparent를 HTTP 헤더로도 보내고 JSON-RPC params._meta로도 보낸다.
반사 백엔드가 받은 것을 그대로 돌려주므로 무엇이 넘어갔는지 알 수 있다.
"""
import argparse, json, sys, time
import httpx

TP = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
TS = "congo=t61rcWkgMzE"


def sse_json(text):
    for line in text.splitlines():
        if line.startswith("data: "):
            try:
                return json.loads(line[6:])
            except json.JSONDecodeError:
                return None
    return None


def run(url, tool):
    c = httpx.Client(timeout=20.0)
    h = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
    r = c.post(url, headers=h, content=json.dumps(
        {"jsonrpc": "2.0", "id": 1, "method": "initialize",
         "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                    "clientInfo": {"name": "trace", "version": "1"}}}))
    sid = r.headers.get("mcp-session-id")
    if sid:
        h["Mcp-Session-Id"] = sid
    c.post(url, headers=h, content=json.dumps(
        {"jsonrpc": "2.0", "method": "notifications/initialized"}))

    out = {}
    for label, extra_headers, meta in (
        ("header_only", {"traceparent": TP, "tracestate": TS}, None),
        ("meta_only", {}, {"traceparent": TP, "tracestate": TS}),
        ("both", {"traceparent": TP, "tracestate": TS}, {"traceparent": TP, "tracestate": TS}),
        ("neither", {}, None),
    ):
        params = {"name": tool, "arguments": {"note": label}}
        if meta:
            params["_meta"] = meta
        rr = c.post(url, headers={**h, **extra_headers}, content=json.dumps(
            {"jsonrpc": "2.0", "id": 9, "method": "tools/call", "params": params}))
        j = sse_json(rr.text)
        seen = None
        try:
            seen = json.loads(j["result"]["content"][0]["text"])
        except Exception:
            seen = {"raw": rr.text[:300], "code": rr.status_code}
        hdrs = seen.get("headers", {}) if isinstance(seen, dict) else {}
        out[label] = {
            "backend_traceparent": hdrs.get("traceparent"),
            "backend_tracestate": hdrs.get("tracestate"),
            "same_trace_id": (hdrs.get("traceparent", "").split("-")[1:2] == TP.split("-")[1:2]
                              if hdrs.get("traceparent") else False),
            "params_meta": seen.get("params_meta") if isinstance(seen, dict) else None,
            "arguments_meta": seen.get("arguments_meta") if isinstance(seen, dict) else None,
            "all_headers": sorted(hdrs.keys()) if hdrs else [],
        }
    c.close()
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--tool", default="reflect__reflect")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    res = {"url": a.url, "tool": a.tool, "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
           "sent_traceparent": TP, "cases": run(a.url, a.tool)}
    import os
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    json.dump(res, open(a.out, "w"), ensure_ascii=False, indent=2)
    for k, v in res["cases"].items():
        print(f"{k:12} backend_tp={v['backend_traceparent']} same_trace={v['same_trace_id']} "
              f"params_meta={v['params_meta']}")
