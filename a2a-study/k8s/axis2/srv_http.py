"""HTTP 구현: 표준 라이브러리 JSON-RPC 서버. 의존성 없음.

[축 2 본측정 델타] 시나리오 2를 위해 앱 수준 핸들을 더했다. `work-start`가 작업
식별자를 돌려주고 `work-status`로 폴링한다. 이 규약은 스펙이 정한 것이 아니라
이 서버가 정한 것이다. 그 사실 자체가 축 2의 결과다.
"""
import json
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, "/app")
from work import work, work_slow

WORK_SECONDS = float(__import__("os").environ.get("WORK_SECONDS", "15"))

# 앱 수준 핸들 저장소. 파드 메모리라 재시작하면 사라진다(축 2에서 그것을 잰다).
JOBS = {}
LOCK = threading.Lock()


def _run(job_id: str, text: str):
    with LOCK:
        JOBS[job_id]["state"] = "running"
    result = work_slow(text, WORK_SECONDS)
    with LOCK:
        JOBS[job_id].update(state="done", result=result)


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        n = int(self.headers.get("content-length", 0) or 0)
        raw = self.rfile.read(n) if n else b"{}"
        try:
            req = json.loads(raw)
            method = req.get("method", "do-work")
            params = req.get("params") or {}
            rid = req.get("id")
            if method in ("do-work", ""):
                self._send(200, {"jsonrpc": "2.0", "id": rid,
                                 "result": {"text": work(params.get("text", ""))}})
            elif method == "do-work-slow":
                self._send(200, {"jsonrpc": "2.0", "id": rid,
                                 "result": {"text": work_slow(params.get("text", ""), WORK_SECONDS)}})
            elif method == "work-start":
                job_id = uuid.uuid4().hex[:12]
                with LOCK:
                    JOBS[job_id] = {"state": "pending", "result": None,
                                    "started": time.time()}
                threading.Thread(target=_run, args=(job_id, params.get("text", "")),
                                 daemon=True).start()
                self._send(200, {"jsonrpc": "2.0", "id": rid,
                                 "result": {"jobId": job_id, "state": "pending"}})
            elif method == "work-status":
                with LOCK:
                    j = JOBS.get(params.get("jobId"))
                if j is None:
                    self._send(200, {"jsonrpc": "2.0", "id": rid,
                                     "error": {"code": -32001, "message": "unknown jobId"}})
                else:
                    self._send(200, {"jsonrpc": "2.0", "id": rid,
                                     "result": {"state": j["state"], "text": j["result"]}})
            elif method == "work-cancel":
                # 취소 규약도 이 서버가 정한 것이다. 실제로 스레드를 멈추지는 못하고
                # 표시만 바꾼다. 앱 수준 핸들의 한계가 그대로 드러나는 자리다.
                with LOCK:
                    j = JOBS.get(params.get("jobId"))
                    if j is not None and j["state"] != "done":
                        j["state"] = "canceled"
                self._send(200, {"jsonrpc": "2.0", "id": rid,
                                 "result": {"state": (j or {}).get("state", "unknown")}})
            else:
                self._send(200, {"jsonrpc": "2.0", "id": rid,
                                 "error": {"code": -32601, "message": "Method not found"}})
        except Exception as e:
            self._send(400, {"jsonrpc": "2.0", "id": None,
                             "error": {"code": -32700, "message": str(e)[:80]}})

    def log_message(self, *a):
        pass


print("http arm listening :9103", flush=True)
ThreadingHTTPServer(("0.0.0.0", 9103), H).serve_forever()
