"""ext_auth(HTTP 모드) 인자 통제 서버. 표준 라이브러리만 쓴다(pip 설치 없음).

agentgateway가 traffic.extAuth.http.body 템플릿으로 만든 JSON을 POST로 보낸다.
그 안의 원본 요청 본문을 JSON-RPC로 읽어 tools/call get-sum은 a == 1일 때만
200(허용), 아니면 403(거부)을 돌려준다. 다른 도구와 다른 메서드는 통과시킨다.
"""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def decide(raw):
    """(허용 여부, 사유). 본문을 못 읽으면 허용(측정 대상은 인자 통제뿐)."""
    try:
        outer = json.loads(raw)
    except Exception:
        return True, "본문 파싱 실패, 통과"
    body = outer.get("body", outer) if isinstance(outer, dict) else outer
    if isinstance(body, str):
        try:
            body = json.loads(body)
        except Exception:
            return True, "내부 본문 파싱 실패, 통과"
    if not isinstance(body, dict) or body.get("method") != "tools/call":
        return True, "tools/call 아님"
    params = body.get("params") or {}
    if params.get("name") != "get-sum":
        return True, "대상 도구 아님"
    args = params.get("arguments") or {}
    if args.get("a") == 1:
        return True, "a == 1"
    return False, "get-sum is allowed only with a == 1"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_POST(self):
        n = int(self.headers.get("content-length", 0) or 0)
        raw = self.rfile.read(n) if n else b""
        allow, why = decide(raw)
        print(f"decide allow={allow} why={why} len={n} raw={raw[:200]!r}", flush=True)
        payload = json.dumps({"allow": allow, "reason": why}).encode()
        self.send_response(200 if allow else 403)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    do_GET = do_POST

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    print("ext_auth listening :8000", flush=True)
    ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
