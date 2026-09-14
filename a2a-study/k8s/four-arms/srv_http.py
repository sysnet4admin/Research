"""HTTP 구현: 표준 라이브러리 JSON-RPC 서버. 의존성 없음."""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, "/app")
from work import work


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_POST(self):
        n = int(self.headers.get("content-length", 0) or 0)
        raw = self.rfile.read(n) if n else b"{}"
        try:
            req = json.loads(raw)
            text = (req.get("params") or {}).get("text", "")
            body = json.dumps({"jsonrpc": "2.0", "id": req.get("id"),
                               "result": {"text": work(text)}}).encode()
            code = 200
        except Exception as e:
            body = json.dumps({"jsonrpc": "2.0", "id": None,
                               "error": {"code": -32700, "message": str(e)[:80]}}).encode()
            code = 400
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


print("http arm listening :9103", flush=True)
ThreadingHTTPServer(("0.0.0.0", 9103), H).serve_forever()
