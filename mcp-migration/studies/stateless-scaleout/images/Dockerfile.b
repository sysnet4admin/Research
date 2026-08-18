# Server B: v2 SDK 의존성 사전 빌드 (pip 런타임 설치 제거)
# 코드는 이미지에 넣지 않고 ConfigMap 마운트 유지 (코드 수정 시 재빌드 불필요)
# 7/28 스펙 확정 시 MCP_VER=2.0.0 (안정판)으로 재빌드
ARG MCP_VER=2.0.0
FROM python:3.12-slim
ARG MCP_VER
RUN pip install --no-cache-dir "mcp==${MCP_VER}" uvicorn redis
EXPOSE 8000
CMD ["python", "/app/server.py"]
