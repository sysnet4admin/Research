#!/usr/bin/env python3
"""이관 전후 페이로드 캡처 (다이어리 발행용, 2026-08-07 추가).

측정이 아니라 기록이 목적이다. 구 스펙과 신 스펙이 같은 일을 할 때 실제로 오가는
HTTP 요청과 응답을 원문 그대로 떠서 다이어리 본문에 싣는다. loadgen.py 의 방언
구성과 같은 규칙을 쓰되, 통계 대신 왕복 하나하나를 남긴다.

캡처 항목:
  A1  initialize        : 세션 발급 (Mcp-Session-Id 응답 헤더)
  A2  initialized 통지
  A3  tools/call        : 세션 헤더를 달고 호출
  A4  세션 유실          : 같은 세션 ID가 다른 파드로 갔을 때의 400
  B1  tools/call        : 핸드셰이크 없이 바로 호출 (헤더 + params._meta)
  B2  counter_create    : 파드 메모리 구현의 핸들 발급
  B3  핸들 유실          : 그 핸들이 다른 파드로 갔을 때의 도구 오류 (이관 함정)
  B4  hcounter_create   : 서명해서 값을 담은 핸들 발급
  B5  hcounter_incr     : 같은 조건에서 파드가 바뀌어도 처리된다 (해법)

사용: python3 harness/capture.py <A_URL> <B_URL> <OUT_DIR>
  예: python3 harness/capture.py http://192.168.2.230/mcp http://192.168.2.231/mcp payloads/
"""

import json
import pathlib
import sys

import httpx

PROTO_A = "2025-11-25"
PROTO_B = "2026-07-28"
META_B = {
    "io.modelcontextprotocol/protocolVersion": PROTO_B,
    "io.modelcontextprotocol/clientInfo": {"name": "capture", "version": "0.1"},
    "io.modelcontextprotocol/clientCapabilities": {},
}
# 응답 헤더 중 기록할 것만 남긴다 (date, server 등 잡음 제거)
PATH = "/mcp"  # 기록용. 실제 경로는 인자 URL에서 온다
KEEP_HEADERS = ("content-type", "mcp-session-id", "mcp-protocol-version")

records = []


def record(label, note, resp, req_headers, req_body):
    """왕복 하나를 구조화해 저장한다."""
    rec = {
        "label": label,
        "note": note,
        "request": {
            "method": "POST",
            "path": PATH,
            "headers": req_headers,
            "body": req_body,
        },
        "response": {
            "status": resp.status_code,
            "headers": {k: v for k, v in resp.headers.items() if k.lower() in KEEP_HEADERS},
            "body": body_of(resp),
        },
    }
    records.append(rec)
    sid = rec["response"]["headers"].get("mcp-session-id", "")
    print(f"  {label:22} {resp.status_code}  {note}{'  sid=' + sid[:8] if sid else ''}")
    return rec


def body_of(resp):
    ctype = resp.headers.get("content-type", "")
    if ctype.startswith("text/event-stream"):
        for line in resp.text.splitlines():
            if line.startswith("data:"):
                try:
                    return json.loads(line[5:].strip())
                except json.JSONDecodeError:
                    continue
        return resp.text
    try:
        return resp.json()
    except Exception:
        return resp.text


def text_result(body):
    if not isinstance(body, dict):
        return ""
    for c in body.get("result", {}).get("content", []):
        if c.get("type") == "text":
            return c.get("text", "")
    return ""


def capture_a(url):
    """구 스펙: 핸드셰이크로 세션을 얻고, 그 세션이 다른 파드로 가면 깨지는 것까지."""
    print("A (구 스펙 2025-11-25)")
    base = {"Accept": "application/json, text/event-stream", "Content-Type": "application/json"}

    with httpx.Client(timeout=20) as c:
        req = {
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {
                "protocolVersion": PROTO_A,
                "capabilities": {},
                "clientInfo": {"name": "capture", "version": "0.1"},
            },
        }
        r = c.post(url, headers=base, json=req)
        rec = record("A1 initialize", "Handshake. The session ID arrives as a response header.", r, base, req)
        sid = r.headers.get("mcp-session-id")
        if not sid:
            print("  [경고] 세션 미발급. 서버가 legacy 세션리스 모드일 수 있다")
            return
        withsid = dict(base, **{"Mcp-Session-Id": sid})

        req = {"jsonrpc": "2.0", "method": "notifications/initialized"}
        r = c.post(url, headers=withsid, json=req)
        record("A2 initialized", "Notification. Two round trips spent before the first tool call.", r, withsid, req)

        req = {
            "jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": {"name": "echo", "arguments": {"message": "ping"}},
        }
        r = c.post(url, headers=withsid, json=req)
        record("A3 tools/call", "The call is served only because it carries the session header.", r, withsid, req)

    # 세션 유실: 매번 새 연결로 같은 세션 ID를 보내면 kube-proxy가 다른 파드로 보낸다
    print("  세션 유실 재현 (연결마다 다른 파드로 분배되기를 기다린다)")
    for i in range(40):
        with httpx.Client(timeout=20) as c:
            req = {
                "jsonrpc": "2.0", "id": 3, "method": "tools/call",
                "params": {"name": "echo", "arguments": {"message": "ping"}},
            }
            r = c.post(url, headers=withsid, json=req)
            if r.status_code in (400, 404):
                record("A4 session lost", f"New connection {i + 1} landed on a pod that never issued this session.",
                       r, withsid, req)
                return
    print("  [주의] 40회 안에 유실이 안 났다. replica 수를 확인할 것")


def capture_b(url):
    """신 스펙: 핸드셰이크 없이 바로 호출하고, 상태는 핸들로 주고받는다."""
    print("B (신 스펙 2026-07-28)")

    def headers(method, name=None):
        h = {
            "Accept": "application/json, text/event-stream",
            "Content-Type": "application/json",
            "MCP-Protocol-Version": PROTO_B,
            "Mcp-Method": method,
        }
        if name:
            h["Mcp-Name"] = name
        return h

    def call(c, name, args, rid):
        h = headers("tools/call", name)
        req = {
            "jsonrpc": "2.0", "id": rid, "method": "tools/call",
            "params": {"name": name, "arguments": args, "_meta": META_B},
        }
        return c.post(url, headers=h, json=req), h, req

    def new_handle(tool, label, note, rid):
        with httpx.Client(timeout=20) as c:
            r, h, req = call(c, tool, {}, rid)
            rec = record(label, note, r, h, req)
        return text_result(rec["response"]["body"])

    def roundtrip(tool, handle, want_fail, label, note):
        """새 연결로 반복 호출한다. 연결마다 파드가 다시 정해진다."""
        for i in range(40):
            with httpx.Client(timeout=20) as c:
                r, h, req = call(c, tool, {"handle": handle}, 10 + i)
                body = body_of(r)
                failed = r.status_code != 200 or "error" in (body or {}) \
                    or (body or {}).get("result", {}).get("isError")
                if failed and want_fail:
                    record(label, note.format(n=i + 1), r, h, req)
                    return True
                if not want_fail and i == 9:
                    record(label, note.format(n=i + 1), r, h, req)
                    return True
                if failed and not want_fail:
                    record(label + " (unexpected failure)", f"Call {i + 1} failed", r, h, req)
                    return False
        return False

    with httpx.Client(timeout=20) as c:
        r, h, req = call(c, "echo", {"message": "ping"}, 1)
        record("B1 tools/call", "No handshake. The first request is served directly.", r, h, req)

    # 이관 함정: 상태를 파드 메모리에 둔 단순 포팅
    mem = new_handle("counter_create", "B2 counter_create",
                     "Pod-memory implementation. The handle only works on the pod that issued it.", 2)
    if mem:
        roundtrip("counter_incr", mem, True, "B3 handle lost",
                  "New connection {n} landed on a pod that does not hold this state.")
    else:
        print("  [경고] 파드 메모리 핸들 발급 실패")

    # 해법: 값을 서명해서 핸들 자체에 담는 구현
    hm = new_handle("hcounter_create", "B4 hcounter_create",
                    "The value is signed into the handle itself. The server stores nothing.", 3)
    if hm:
        roundtrip("hcounter_incr", hm, False, "B5 hcounter_incr",
                  "Served across {n} round trips on new connections, whichever pod answered.")
    else:
        print("  [경고] 서명 핸들 발급 실패")


def render_md(recs, state=None):
    """다이어리에 붙일 수 있는 형태로 왕복을 옮긴다."""
    out = ["# Captured payloads", "",
           "Verbatim request and response pairs from the running cluster.",
           "Response headers are filtered to the ones that carry protocol meaning.", ""]
    if state:
        out += ["Replicas at capture time: "
                + ", ".join(f"`{k}` {v}" for k, v in sorted(state.items())), ""]
    for r in recs:
        req, resp = r["request"], r["response"]
        out += [f"## {r['label']}", "", r["note"], "", "```http",
                f"{req['method']} {req['path']}"]
        out += [f"{k}: {v}" for k, v in req["headers"].items()]
        out += ["", json.dumps(req["body"], indent=2, ensure_ascii=False), "```", "",
                "```http", f"HTTP/1.1 {resp['status']}"]
        out += [f"{k}: {v}" for k, v in resp["headers"].items()]
        body = resp["body"]
        out += ["", body if isinstance(body, str) else json.dumps(body, indent=2, ensure_ascii=False),
                "```", ""]
    return "\n".join(out)


def deploy_state():
    """캡처 시점의 replica 수를 남긴다.

    "몇 번째 연결에서 유실이 났다"는 서술은 replica 수가 없으면 검증할 수 없다.
    kubectl이 없거나 실패하면 조용히 건너뛴다(캡처 자체를 막지 않는다).
    """
    import subprocess

    try:
        out = subprocess.run(
            ["kubectl", "--context", "mcp-migration", "-n", "mcp-pilot", "get", "deploy",
             "-o", "jsonpath={range .items[*]}{.metadata.name}={.status.readyReplicas}{'\\n'}{end}"],
            capture_output=True, text=True, timeout=20, check=True).stdout
        return dict(l.split("=", 1) for l in out.strip().splitlines() if "=" in l)
    except Exception:
        return {}


if __name__ == "__main__":
    a_url, b_url, out = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
    globals()["PATH"] = "/" + a_url.split("/", 3)[3] if a_url.count("/") > 2 else "/"
    out.mkdir(parents=True, exist_ok=True)
    state = deploy_state()
    if state:
        print("replicas:", ", ".join(f"{k}={v}" for k, v in sorted(state.items())))
    capture_a(a_url)
    capture_b(b_url)
    doc = {"replicas": state, "records": records}
    (out / "payloads.json").write_text(json.dumps(doc, indent=2, ensure_ascii=False))
    (out / "payloads.md").write_text(render_md(records, state))
    print(f"\n{len(records)}건 저장: {out}/payloads.json, payloads.md")
