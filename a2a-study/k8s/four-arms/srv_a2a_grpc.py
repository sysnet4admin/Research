"""오버헤드 측정용 A2A 구현에 gRPC 바인딩을 더한 것.

k8s/three-arms/srv_a2a.py의 최소 델타 사본이다. 같은 핸들러를 JSON-RPC와 gRPC
양쪽으로 열어 네 번째 구현을 만든다. 1, 2회차는 gRPC 없이 돌았으므로 이 구성의
회차는 따로 기록한다.

원래 주석은 아래에 둔다.

A2A 구현: 공식 a2a-sdk 1.1.2. 실행기가 공유 작업 함수를 호출한다.

스파이크 2와 3의 서버에서 실행기 본문만 바꾼 최소 델타다. 카드와 라우트 구성은
그대로 두어 SDK 기본 동작을 유지한다.
"""
import asyncio
import os
import sys

import uvicorn
from fastapi import FastAPI

sys.path.insert(0, "/app")
from work import work

from a2a.server.agent_execution.agent_executor import AgentExecutor
from a2a.server.agent_execution.context import RequestContext
from a2a.server.events.event_queue import EventQueue
from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.routes import (
    add_a2a_routes_to_fastapi,
    create_agent_card_routes,
    create_jsonrpc_routes,
    create_rest_routes,
)
from a2a.server.tasks.inmemory_task_store import InMemoryTaskStore
from a2a.server.tasks.task_updater import TaskUpdater
from a2a.types import (
    AgentCapabilities,
    AgentCard,
    AgentInterface,
    AgentProvider,
    AgentSkill,
    Part,
    Task,
    TaskState,
    TaskStatus,
)


class WorkExecutor(AgentExecutor):
    async def cancel(self, context: RequestContext, event_queue: EventQueue) -> None:
        updater = TaskUpdater(event_queue=event_queue, task_id=context.task_id or "",
                              context_id=context.context_id or "")
        await updater.cancel()

    async def execute(self, context: RequestContext, event_queue: EventQueue) -> None:
        task_id, context_id = context.task_id, context.context_id
        if not context.message or not task_id or not context_id:
            return
        await event_queue.enqueue_event(
            Task(id=task_id, context_id=context_id,
                 status=TaskStatus(state=TaskState.TASK_STATE_SUBMITTED),
                 history=[context.message])
        )
        updater = TaskUpdater(event_queue=event_queue, task_id=task_id, context_id=context_id)
        await updater.start_work()
        await updater.add_artifact(parts=[Part(text=work(context.get_user_input()))],
                                   name="response", last_chunk=True)
        await updater.complete()


async def serve_grpc(handler, host: str, port: int) -> None:
    """같은 핸들러를 gRPC로도 연다. JSON-RPC와 같은 태스크 저장소를 쓴다."""
    import grpc
    from a2a.server.request_handlers.grpc_handler import GrpcHandler
    from a2a.types import a2a_pb2_grpc

    server = grpc.aio.server()
    a2a_pb2_grpc.add_A2AServiceServicer_to_server(
        GrpcHandler(request_handler=handler), server
    )
    server.add_insecure_port(f"{host}:{port}")
    await server.start()
    print(f"a2a grpc listening :{port}", flush=True)
    await server.wait_for_termination()


async def serve(host: str = "0.0.0.0", port: int = 9101) -> None:
    card_host = os.environ.get("CARD_HOST", f"{host}:{port}")
    card = AgentCard(
        name="Three Arms Agent",
        description="Runs the shared work function over A2A.",
        provider=AgentProvider(organization="a2a-study", url="https://example.com"),
        version="1.0.0",
        capabilities=AgentCapabilities(streaming=True, push_notifications=False),
        default_input_modes=["text"],
        default_output_modes=["text"],
        skills=[AgentSkill(id="do_work", name="do work", description="Runs the shared work function.",
                           tags=["work"], examples=["hi"], input_modes=["text"], output_modes=["text"])],
        supported_interfaces=[
            AgentInterface(protocol_binding="JSONRPC", protocol_version="1.0",
                           url=f"http://{card_host}/a2a/jsonrpc"),
            AgentInterface(protocol_binding="JSONRPC", protocol_version="0.3",
                           url=f"http://{card_host}/a2a/jsonrpc"),
            AgentInterface(protocol_binding="GRPC", protocol_version="1.0",
                           url=f"{os.environ.get('GRPC_HOST', card_host.split(':')[0])}:9111"),
        ],
    )
    handler = DefaultRequestHandler(agent_executor=WorkExecutor(), task_store=InMemoryTaskStore(),
                                    agent_card=card)
    app = FastAPI()
    add_a2a_routes_to_fastapi(
        app,
        agent_card_routes=create_agent_card_routes(agent_card=card),
        jsonrpc_routes=create_jsonrpc_routes(request_handler=handler, rpc_url="/a2a/jsonrpc",
                                             enable_v0_3_compat=True),
        rest_routes=create_rest_routes(request_handler=handler, path_prefix="/a2a/rest",
                                       enable_v0_3_compat=True),
    )
    print("a2a arm listening :9101", flush=True)
    grpc_port = int(os.environ.get("GRPC_PORT", "9111"))
    await asyncio.gather(
        uvicorn.Server(uvicorn.Config(app, host=host, port=port, log_level="warning")).serve(),
        serve_grpc(handler, host, grpc_port),
    )


if __name__ == "__main__":
    asyncio.run(serve())
