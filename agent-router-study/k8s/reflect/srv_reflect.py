#!/usr/bin/env python3
"""받은 것을 그대로 돌려주는 MCP 서버. 게이트웨이가 무엇을 넘기는지 보려고 쓴다.

도구는 둘이다. reflect는 HTTP 헤더와 JSON-RPC params의 _meta를 결과로 돌려주고,
get-sum은 인자 조건 정책을 이 백엔드에서도 걸 수 있게 mcp-b와 같은 모양으로 둔다.
Streamable HTTP 하나만 다루고 세션은 무상태로 처리한다.
"""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PROTO = "2025-06-18"
TOOLS = [
    {"name": "reflect", "description": "받은 헤더와 _meta를 돌려준다",
     "inputSchema": {"type": "object", "properties": {"note": {"type": "string"}}}},
    {"name": "get-sum", "description": "a와 b를 더한다",
     "inputSchema": {"type": "object",
                     "properties": {"a": {"type": "number"}, "b": {"type": "number"}},
                     "required": ["a", "b"]}},
]


def result(rid, payload):
    return {"jsonrpc": "2.0", "id": rid, "result": payload}


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _send(self, obj, code=200):
        body = ("event: message\ndata: " + json.dumps(obj) + "\n\n").encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Mcp-Session-Id", "reflect-session")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        req = json.loads(self.rfile.read(n) or b"{}")
        method, rid = req.get("method"), req.get("id")
        params = req.get("params") or {}

        if method == "initialize":
            return self._send(result(rid, {
                "protocolVersion": PROTO, "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {"name": "reflect", "version": "1"}}))
        if rid is None:
            self.send_response(202)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if method == "tools/list":
            return self._send(result(rid, {"tools": TOOLS}))
        if method == "tools/call":
            name = params.get("name")
            args = params.get("arguments") or {}
            if name == "get-sum":
                total = float(args.get("a", 0)) + float(args.get("b", 0))
                return self._send(result(rid, {"content": [{"type": "text", "text": str(total)}],
                                               "isError": False}))
            seen = {
                "headers": {k.lower(): v for k, v in self.headers.items()},
                "params_meta": params.get("_meta"),
                "arguments_meta": args.get("_meta"),
            }
            return self._send(result(rid, {
                "content": [{"type": "text", "text": json.dumps(seen, ensure_ascii=False)}],
                "isError": False}))
        return self._send({"jsonrpc": "2.0", "id": rid,
                           "error": {"code": -32601, "message": "method not found"}})


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 9200), H).serve_forever()
