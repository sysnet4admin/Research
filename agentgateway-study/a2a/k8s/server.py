# 본측정용 최소 A2A 에이전트 (표준 라이브러리만, SDK 미사용).
# 스파이크판(spike/a2a-spike-0827/k8s/server.py)에서 승격. 추가된 것:
# - CARD_FORMAT env로 카드 형식 전환 (v03 | v10 | both). 축 A 매트릭스용.
# - message/send 응답 metadata에 수신 헤더와 수신 메시지 metadata를 되돌려
#   준다. 게이트웨이가 무엇을 바꿔/넣어 보냈는지 호스트에서 판독하는 용도
#   (축 B: traceparent 전파, metadata 주입).
# - ThreadingHTTPServer + HTTP/1.1 (keep-alive). 축 C의 reuse 경로가 실제로
#   연결을 재사용하려면 서버가 1.1이어야 한다(스파이크판은 1.0이라 매 요청
#   연결 종료였다).
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DIRECT_URL = os.environ.get(
    "DIRECT_URL", "http://a2a-echo.mcp-pilot.svc.cluster.local:9999/")
CARD_FORMAT = os.environ.get("CARD_FORMAT", "v03")  # v03 | v10 | both

# 판독에 쓰는 수신 헤더만 되돌린다 (전체 반사는 노이즈)
ECHO_HEADERS = ("traceparent", "tracestate", "host", "x-request-id",
                "x-forwarded-for", "x-forwarded-proto", "user-agent")


def build_card():
    card = {
        "name": "a2a-echo",
        "description": "A2A echo agent (measurement)",
        "version": "0.3.0",
        "capabilities": {"streaming": False},
        "defaultInputModes": ["text"],
        "defaultOutputModes": ["text"],
        "skills": [{"id": "echo", "name": "echo",
                    "description": "echo text back", "tags": ["measure"]}],
    }
    if CARD_FORMAT in ("v03", "both"):
        card["url"] = DIRECT_URL          # v0.3 스타일 최상위 url
    if CARD_FORMAT in ("v10", "both"):
        card["supportedInterfaces"] = [   # v1.0 스타일
            {"url": DIRECT_URL, "transport": "JSONRPC"}]
    return card


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    # 필수. 헤더와 본문이 두 세그먼트로 나가는데 Nagle이 켜져 있으면 두 번째
    # 세그먼트가 상대의 delayed ACK(~40ms)를 기다린다. 켠 채 측정한 abm-0827
    # 첫 셀에서 게이트웨이 경유 p50이 46.5ms로 나온 원인(게이트웨이-백엔드
    # keep-alive 구간에서 발현). 게이트웨이 비용 측정을 40ms 아티팩트가
    # 삼키므로 반드시 끈다.
    disable_nagle_algorithm = True

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.endswith("/.well-known/agent.json") or \
           self.path.endswith("/.well-known/agent-card.json"):
            self._send(200, build_card())
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        try:
            req = json.loads(self.rfile.read(n))
        except Exception:
            return self._send(400, {"error": "bad json"})
        method = req.get("method", "")
        rid = req.get("id")
        if method == "message/send":
            msg = (req.get("params", {}) or {}).get("message", {}) or {}
            parts = msg.get("parts", [])
            text = next((p.get("text", "") for p in parts
                         if p.get("kind") == "text"), "")
            self._send(200, {"jsonrpc": "2.0", "id": rid, "result": {
                "kind": "message", "role": "agent", "messageId": "m-1",
                "parts": [{"kind": "text", "text": f"Echo: {text}"}],
                "metadata": {
                    "received_headers": {
                        k: self.headers[k] for k in ECHO_HEADERS
                        if self.headers.get(k) is not None},
                    "received_message_metadata": msg.get("metadata"),
                }}})
        else:
            self._send(200, {"jsonrpc": "2.0", "id": rid, "error": {
                "code": -32601, "message": f"Method not found: {method}"}})

    def log_message(self, *a):
        pass


print(f"a2a echo agent on :9999 (card={CARD_FORMAT})", flush=True)
ThreadingHTTPServer(("0.0.0.0", 9999), H).serve_forever()
