#!/usr/bin/env python3
"""두 스펙으로 같은 도구를 호출하는 최소 클라이언트 (SDK 없이 raw HTTP).

이관할 때 실제로 무엇이 달라지는지는 이 두 함수의 차이가 전부다. SDK를 쓰면
자동으로 채워지는 부분까지 눈에 보이게 직접 만든다.

사용:
  python3 examples/minimal_client.py old http://<A_LB_IP>/mcp
  python3 examples/minimal_client.py new http://<B_LB_IP>/mcp
"""

import json
import sys

import httpx

JSON_HEADERS = {
    "Accept": "application/json, text/event-stream",
    "Content-Type": "application/json",
}


def result_text(resp):
    """JSON 응답과 SSE 응답 양쪽에서 도구 결과 문자열을 꺼낸다."""
    if resp.headers.get("content-type", "").startswith("text/event-stream"):
        body = None
        for line in resp.text.splitlines():
            if line.startswith("data:"):
                obj = json.loads(line[5:].strip())
                if "result" in obj or "error" in obj:
                    body = obj
    else:
        body = resp.json()
    for c in (body or {}).get("result", {}).get("content", []):
        if c.get("type") == "text":
            return c["text"]
    return json.dumps(body)


def call_old_spec(url, message):
    """2025-11-25: 핸드셰이크 2회로 세션을 얻고 그 세션으로 호출한다.

    같은 연결을 계속 써야 한다. 연결이 끊기면 세션도 함께 잃는다.
    """
    with httpx.Client(timeout=20) as c:
        r = c.post(url, headers=JSON_HEADERS, json={
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {
                "protocolVersion": "2025-11-25",
                "capabilities": {},
                "clientInfo": {"name": "minimal", "version": "0.1"},
            },
        })
        r.raise_for_status()
        session = r.headers.get("mcp-session-id")
        if not session:
            raise RuntimeError("서버가 세션을 발급하지 않았다")
        headers = dict(JSON_HEADERS, **{"Mcp-Session-Id": session})

        c.post(url, headers=headers,
               json={"jsonrpc": "2.0", "method": "notifications/initialized"})

        r = c.post(url, headers=headers, json={
            "jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": {"name": "echo", "arguments": {"message": message}},
        })
        return result_text(r)


def call_new_spec(url, message):
    """2026-07-28: 핸드셰이크가 없다. 요청 하나가 스스로를 설명한다.

    연결이 끊겨도, 다른 파드가 받아도 그대로 처리된다.
    """
    headers = dict(JSON_HEADERS, **{
        "MCP-Protocol-Version": "2026-07-28",
        "Mcp-Method": "tools/call",
        "Mcp-Name": "echo",
    })
    with httpx.Client(timeout=20) as c:
        r = c.post(url, headers=headers, json={
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": {
                "name": "echo",
                "arguments": {"message": message},
                "_meta": {
                    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
                    "io.modelcontextprotocol/clientInfo": {"name": "minimal", "version": "0.1"},
                    "io.modelcontextprotocol/clientCapabilities": {},
                },
            },
        })
        return result_text(r)


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] not in ("old", "new"):
        print(__doc__)
        sys.exit(2)
    spec, url = sys.argv[1], sys.argv[2]
    fn = call_old_spec if spec == "old" else call_new_spec
    print(fn(url, "hello"))
