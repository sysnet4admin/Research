"""MCP 구현: 공식 파이썬 SDK 2.0.0(2026-07-28 스테이트리스), 도구 이름 do-work."""
import sys

sys.path.insert(0, "/app")
from work import work

from mcp.server import MCPServer
from mcp.server.transport_security import TransportSecuritySettings

mcp = MCPServer("three-arms-mcp")


@mcp.tool(name="do-work")
def do_work(text: str) -> str:
    """Runs the shared work function"""
    return work(text)


if __name__ == "__main__":
    import uvicorn

    # 기존 b-server와 같은 설정: 격리 사설망이라 DNS rebinding 보호를 끈다.
    app = mcp.streamable_http_app(
        transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False)
    )
    print("mcp arm listening :9102", flush=True)
    uvicorn.run(app, host="0.0.0.0", port=9102, log_level="warning")
