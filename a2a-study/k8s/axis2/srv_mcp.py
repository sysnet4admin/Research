"""MCP 구현: 공식 파이썬 SDK 2.0.0(2026-07-28 스테이트리스), 도구 이름 do-work.

[축 2 본측정 델타] 시나리오 2를 위해 두 경로를 더했다.
  (a) `do-work-slow`  15초를 그대로 기다리는 차단 호출
  (b) `work-start` / `work-status` / `work-cancel`  앱 수준 핸들

**mcp 2.0.0 코어에는 태스크 수명주기가 없다.** `resultType`(필수, 코어 값은
`complete`)만 있고 `tasks/*`는 확장이 서브하는 메서드로만 언급된다. 그래서
장시간 작업의 진행 확인을 프로토콜이 아니라 도구 이름으로 만들어야 한다. 이
구조 자체가 축 2의 결과다.
"""
import asyncio
import os
import sys
import time
import uuid

sys.path.insert(0, "/app")
from work import work, work_slow_async

from mcp.server import MCPServer
from mcp.server.transport_security import TransportSecuritySettings

WORK_SECONDS = float(os.environ.get("WORK_SECONDS", "15"))

mcp = MCPServer("axis2-mcp")

# 앱 수준 핸들 저장소. 파드 메모리라 재시작하면 사라진다.
JOBS: dict[str, dict] = {}


@mcp.tool(name="do-work")
def do_work(text: str) -> str:
    """Runs the shared work function"""
    return work(text)


@mcp.tool(name="do-work-slow")
async def do_work_slow(text: str) -> str:
    """Runs the shared work function, blocking for the configured duration"""
    return await work_slow_async(text, WORK_SECONDS)


async def _run(job_id: str, text: str) -> None:
    JOBS[job_id]["state"] = "running"
    result = await work_slow_async(text, WORK_SECONDS)
    if JOBS[job_id]["state"] != "canceled":
        JOBS[job_id].update(state="done", result=result)


@mcp.tool(name="work-start")
async def work_start(text: str) -> str:
    """Starts the long work and returns an application-level job id"""
    job_id = uuid.uuid4().hex[:12]
    JOBS[job_id] = {"state": "pending", "result": None, "started": time.time()}
    asyncio.create_task(_run(job_id, text))
    return job_id


@mcp.tool(name="work-status")
def work_status(job_id: str) -> str:
    """Returns the state of a job started by work-start"""
    j = JOBS.get(job_id)
    if j is None:
        return "unknown"
    return j["state"] if j["state"] != "done" else f"done:{j['result']}"


@mcp.tool(name="work-cancel")
def work_cancel(job_id: str) -> str:
    """Marks a job canceled. The work itself keeps running."""
    j = JOBS.get(job_id)
    if j is None:
        return "unknown"
    if j["state"] != "done":
        j["state"] = "canceled"
    return j["state"]


if __name__ == "__main__":
    import uvicorn

    # 기존 b-server와 같은 설정: 격리 사설망이라 DNS rebinding 보호를 끈다.
    app = mcp.streamable_http_app(
        transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False)
    )
    print("mcp arm listening :9102", flush=True)
    uvicorn.run(app, host="0.0.0.0", port=9102, log_level="warning")
