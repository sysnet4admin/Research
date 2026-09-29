#!/usr/bin/env python3
"""실제 도구와 실제 클라이언트 보강 측정(2026-09-28) 중 측정 2. 공식 MCP Python SDK 클라이언트가 게이트웨이의 거부를
받았을 때 무엇을 하는지 기록한다(오류로 끝나나, 재시도하나, 재인증을 시도하나).

HTTP 클라이언트에 이벤트 훅을 걸어 SDK 가 실제로 보낸 요청을 전부 적는다. 재시도와
재인증 시도는 이 목록에서 판정한다(같은 요청의 반복, OAuth 메타데이터나 토큰 경로 요청).
거부 뒤 같은 세션으로 허용된 호출을 한 번 더 보내 세션이 살아 있는지도 본다.

사용: ~/.venvs/mcpsdk/bin/python sdk_reject_probe.py --url <MCP URL> --denied <도구> \
        --denied-args '<json>' --allowed <도구> --allowed-args '<json>' --label <이름> --out <파일>
"""
import argparse, asyncio, importlib.metadata as md, json, time, traceback

import httpx2
from mcp import Client
from mcp.client.streamable_http import streamable_http_client


async def main():
    ap = argparse.ArgumentParser()
    for k in ("url", "denied", "denied-args", "allowed", "allowed-args", "label", "out"):
        ap.add_argument(f"--{k}", required=True)
    a = ap.parse_args()

    log = []

    async def on_request(req):
        body = req.content.decode(errors="replace") if req.content else ""
        m = ""
        try:
            m = json.loads(body).get("method", "") if body else ""
        except Exception:
            pass
        log.append({"t": time.time(), "dir": "req", "method": req.method, "url": str(req.url),
                    "mcp": m, "auth": "authorization" in {k.lower() for k in req.headers}})

    async def on_response(resp):
        log.append({"t": time.time(), "dir": "resp", "url": str(resp.request.url),
                    "status": resp.status_code,
                    "www_authenticate": resp.headers.get("www-authenticate", "")})

    rec = {"label": a.label, "url": a.url, "sdk": "mcp " + md.version("mcp"), "steps": {}}
    http = httpx2.AsyncClient(event_hooks={"request": [on_request], "response": [on_response]},
                              timeout=30)

    def outcome(fn_result=None, exc=None):
        if exc is not None:
            return {"raised": type(exc).__name__, "message": str(exc)[:300]}
        r = fn_result
        d = r.model_dump(by_alias=True) if hasattr(r, "model_dump") else r
        return {"raised": None, "isError": d.get("isError"),
                "content": json.dumps(d.get("content"))[:300]}

    try:
        async with Client(streamable_http_client(a.url, http_client=http)) as c:
            t0 = len(log)
            tools = await c.list_tools()
            rec["steps"]["list_tools"] = {"names": [t.name for t in tools.tools][:40],
                                          "count": len(tools.tools)}
            t1 = len(log)
            try:
                res = await c.call_tool(a.denied, json.loads(a.denied_args))
                rec["steps"]["denied_call"] = outcome(res)
            except Exception as e:  # noqa: BLE001 - 무엇이 올라오는지가 측정 대상이다
                rec["steps"]["denied_call"] = outcome(exc=e)
            rec["steps"]["denied_call"]["http_requests"] = [x for x in log[t1:] if x["dir"] == "req"]
            rec["steps"]["denied_call"]["http_responses"] = [x for x in log[t1:] if x["dir"] == "resp"]
            t2 = len(log)
            try:
                res = await c.call_tool(a.allowed, json.loads(a.allowed_args))
                rec["steps"]["allowed_after"] = outcome(res)
            except Exception as e:  # noqa: BLE001
                rec["steps"]["allowed_after"] = outcome(exc=e)
            rec["steps"]["allowed_after"]["http_requests"] = len([x for x in log[t2:] if x["dir"] == "req"])
    except Exception as e:  # noqa: BLE001
        rec["session_error"] = {"raised": type(e).__name__, "message": str(e)[:300],
                                "trace": traceback.format_exc()[-800:]}

    reqs = [x for x in log if x["dir"] == "req"]
    rec["summary"] = {
        "total_http_requests": len(reqs),
        "requests_during_denied_call": len(rec["steps"].get("denied_call", {}).get("http_requests", [])),
        "oauth_or_wellknown_requests": [x["url"] for x in reqs
                                        if "well-known" in x["url"] or "oauth" in x["url"] or "token" in x["url"]],
        "requests_with_authorization_header": sum(1 for x in reqs if x["auth"]),
        "www_authenticate_seen": sorted({x["www_authenticate"] for x in log
                                         if x["dir"] == "resp" and x.get("www_authenticate")}),
    }
    rec["http_log"] = log
    with open(a.out, "w") as f:
        json.dump(rec, f, ensure_ascii=False, indent=1)
    dc = rec["steps"].get("denied_call", {})
    print(f"{a.label}: denied -> raised={dc.get('raised')} isError={dc.get('isError')} "
          f"msg={(dc.get('message') or dc.get('content') or '')[:90]!r} "
          f"reqs={rec['summary']['requests_during_denied_call']} "
          f"oauth={len(rec['summary']['oauth_or_wellknown_requests'])} "
          f"after={rec['steps'].get('allowed_after', {}).get('raised') or 'ok'}"
          + (f" SESSION_ERROR={rec['session_error']['raised']}" if "session_error" in rec else ""))
    await http.aclose()


if __name__ == "__main__":
    asyncio.run(main())
