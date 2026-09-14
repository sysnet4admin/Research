#!/usr/bin/env python3
"""A2A의 gRPC 바인딩을 JSON-RPC와 견준다.

1단계에서 gRPC를 재지 않아 트랜스포트 동등성 판정에 "gRPC는 재지 않았다"가
남아 있었다. 이 프로브가 그것을 없앤다.

재는 것은 셋이다.
- 동등성: 같은 요청이 gRPC로도 같은 결과를 내는가.
- 크기: 직렬화된 응답 메시지가 몇 바이트인가. HTTP/2 프레이밍과 헤더 압축은
  빼고 메시지 본문만 센다. JSON-RPC 쪽은 HTTP 본문 바이트라 같은 기준이 아니다.
  그 차이를 결과에 함께 적는다.
- 지연: 같은 호출을 N회 반복한 왕복 시간의 p50.

사용: ./grpc_probe.py --host <IP> [--reps 30]
"""
import argparse
import json
import statistics
import time
import urllib.request

import grpc
from a2a.types import a2a_pb2, a2a_pb2_grpc


def jsonrpc_call(url, body, headers=None):
    data = json.dumps(body).encode()
    req = urllib.request.Request(url, data=data,
                                 headers={"Content-Type": "application/json", **(headers or {})})
    t0 = time.perf_counter()
    with urllib.request.urlopen(req, timeout=30) as r:
        raw = r.read()
    return time.perf_counter() - t0, len(raw), json.loads(raw)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--host", required=True)
    ap.add_argument("--jsonrpc-port", type=int, default=9101)
    ap.add_argument("--grpc-port", type=int, default=9111)
    ap.add_argument("--reps", type=int, default=30)
    ap.add_argument("--text", default="fast:hello-world")
    a = ap.parse_args()

    out = {"host": a.host, "reps": a.reps, "text": a.text}
    jurl = f"http://{a.host}:{a.jsonrpc_port}/a2a/jsonrpc"

    # 1. JSON-RPC v1.0 기준값
    body = {"jsonrpc": "2.0", "id": 1, "method": "SendMessage",
            "params": {"message": {"role": "ROLE_USER", "messageId": "g1",
                                   "parts": [{"text": a.text}]}}}
    lat, size, obj = jsonrpc_call(jurl, body, {"A2A-Version": "1.0"})
    task = (obj.get("result") or {}).get("task") or {}
    out["jsonrpc_v10"] = {"bytes": size, "state": (task.get("status") or {}).get("state")}

    # 2. gRPC 한 번
    ch = grpc.insecure_channel(f"{a.host}:{a.grpc_port}")
    stub = a2a_pb2_grpc.A2AServiceStub(ch)
    msg = a2a_pb2.Message(role=a2a_pb2.ROLE_USER, message_id="g2")
    msg.parts.add().text = a.text
    req = a2a_pb2.SendMessageRequest(message=msg)
    t0 = time.perf_counter()
    resp = stub.SendMessage(req, timeout=30)
    lat_grpc = time.perf_counter() - t0
    out["grpc"] = {"serialized_bytes": len(resp.SerializeToString()),
                   "state": a2a_pb2.TaskState.Name(resp.task.status.state)
                   if resp.HasField("task") else "(task 아님)"}

    # 3. 지연 반복
    jl, gl = [], []
    for i in range(a.reps):
        b = json.loads(json.dumps(body))
        b["params"]["message"]["messageId"] = f"j{i}"
        jl.append(jsonrpc_call(jurl, b, {"A2A-Version": "1.0"})[0] * 1000)
        m = a2a_pb2.Message(role=a2a_pb2.ROLE_USER, message_id=f"g{i}")
        m.parts.add().text = a.text
        t0 = time.perf_counter()
        stub.SendMessage(a2a_pb2.SendMessageRequest(message=m), timeout=30)
        gl.append((time.perf_counter() - t0) * 1000)
    q = lambda v: {"p50": round(statistics.median(v), 2),
                   "p90": round(sorted(v)[int(len(v) * 0.9) - 1], 2)}
    out["latency_ms"] = {"jsonrpc_v10": q(jl), "grpc": q(gl)}

    # 4. 동등성: 결과 문자열이 같은가
    art = ""
    if resp.HasField("task") and resp.task.artifacts:
        p = resp.task.artifacts[0].parts
        if p:
            art = p[0].text
    jart = ""
    for A in (task.get("artifacts") or []):
        for p in (A.get("parts") or []):
            jart = p.get("text", "")
    out["equivalence"] = {"grpc_artifact": art, "jsonrpc_artifact": jart,
                          "same": art == jart and art != ""}
    ch.close()
    print(json.dumps(out, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
