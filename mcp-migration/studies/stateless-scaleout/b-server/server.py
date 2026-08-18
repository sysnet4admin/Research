"""Pilot server B: MCP 2026-07-28 (stateless) port of the everything-server workload subset.

Python SDK v2 (mcp==2.0.0 안정 버전. 7월 파일럿은 2.0.0b1로 시작해
포팅했고 안정판에서 수정 없이 그대로 돌았다). Tools:
- echo, get-sum          : everything 서버와 같은 워크로드 (stateless 비교용)
- counter_create/_incr   : in-memory handle (naive 포팅의 병리 재현용. 파드마다 딴 Map)
- hcounter_create/_incr  : self-contained handle (HMAC 서명, 어느 replica든 처리 가능)

handle 오류는 도구 수준 오류(isError)로 표면화된다(스펙이 앱 재량에 맡김).
"""

import hashlib
import hmac
import os
import uuid

from mcp.server import MCPServer
from mcp.server.transport_security import TransportSecuritySettings

mcp = MCPServer("pilot-b")

# ---- stateless workload (everything 서버와 동일 이름/스키마) ----


@mcp.tool(name="echo")
def echo(message: str) -> str:
    """Echoes back the input string"""
    return f"Echo: {message}"


@mcp.tool(name="get-sum")
def get_sum(a: float, b: float) -> str:
    """Adds two numbers"""
    return str(a + b)


# ---- in-memory handle: naive 포팅 (파드 로컬 상태) ----

_COUNTERS: dict[str, int] = {}
_POD = os.environ.get("HOSTNAME", "unknown")


@mcp.tool(name="counter_create")
def counter_create() -> str:
    """Create a counter, returns its handle (in-memory, pod-local)"""
    h = uuid.uuid4().hex
    _COUNTERS[h] = 0
    return h


@mcp.tool(name="counter_incr")
def counter_incr(handle: str) -> str:
    """Increment a counter by handle (in-memory, pod-local)"""
    if handle not in _COUNTERS:
        # 스펙이 미규정한 지점: unknown handle은 도구 수준 오류로 반환
        raise ValueError(f"unknown handle (pod={_POD})")
    _COUNTERS[handle] += 1
    return str(_COUNTERS[handle])


# ---- Redis 백엔드 handle: 외부화된 공유 상태 (어느 replica든 처리 가능) ----

_REDIS = None


def _redis():
    global _REDIS
    if _REDIS is None:
        import redis

        # 주의: REDIS_HOST/REDIS_PORT는 쓰지 않는다. 서비스 이름이 redis라
        # kubelet이 REDIS_PORT=tcp://<ip>:6379 (링크 스타일)를 자동 주입해 충돌한다.
        _REDIS = redis.Redis(
            host=os.environ.get("HANDLE_REDIS_HOST", "redis"),
            port=int(os.environ.get("HANDLE_REDIS_PORT", "6379")),
            socket_timeout=2,
        )
    return _REDIS


@mcp.tool(name="rcounter_create")
def rcounter_create() -> str:
    """Create a counter backed by Redis (shared across replicas)"""
    h = uuid.uuid4().hex
    _redis().set(f"ctr:{h}", 0, ex=3600)
    return h


@mcp.tool(name="rcounter_incr")
def rcounter_incr(handle: str) -> str:
    """Increment a Redis-backed counter by handle"""
    key = f"ctr:{handle}"
    if not _redis().exists(key):
        raise ValueError(f"unknown handle (pod={_POD})")
    return str(_redis().incr(key))


# ---- self-contained handle: HMAC 서명, 상태를 handle 안에 내장 ----

_KEY = os.environ.get("HANDLE_KEY", "pilot-shared-key").encode()


def _sign(value: int) -> str:
    payload = str(value)
    sig = hmac.new(_KEY, payload.encode(), hashlib.sha256).hexdigest()[:16]
    return f"v{payload}:{sig}"


def _verify(handle: str) -> int:
    try:
        payload, sig = handle.rsplit(":", 1)
        value = int(payload[1:])
    except (ValueError, IndexError):
        raise ValueError("malformed handle")
    if not hmac.compare_digest(
        sig, hmac.new(_KEY, str(value).encode(), hashlib.sha256).hexdigest()[:16]
    ):
        raise ValueError("bad handle signature")
    return value


@mcp.tool(name="hcounter_create")
def hcounter_create() -> str:
    """Create a self-contained counter handle (works on any replica)"""
    return _sign(0)


@mcp.tool(name="hcounter_incr")
def hcounter_incr(handle: str) -> str:
    """Increment a self-contained counter, returns new handle"""
    value = _verify(handle) + 1
    return _sign(value)


# ---- ASGI app ----

# LB IP로 접근하므로 DNS rebinding 보호를 끈다 (격리 사설망 측정 전용).
# allowed_hosts는 "*" 미지원(host:* 포트 와일드카드만)이라 LB IP가 유동인 환경에서
# 열거가 불가능함 -> enable_dns_rebinding_protection=False가 SDK가 제공하는 유일한 우회
# (2026-07-07 mcp==2.0.0b1 transport_security.py 확인, 미설정 시 기본값도 False).
security = TransportSecuritySettings(enable_dns_rebinding_protection=False)
app = mcp.streamable_http_app(transport_security=security)

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="warning")
