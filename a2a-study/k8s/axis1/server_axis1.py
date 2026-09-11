# [축 1 본측정] 스파이크 4 서버(server4.py)의 최소 델타. 스파이크에서 확인한 것을 그대로 두고
# 축 1 항목표에 남은 것을 켤 수 있게 환경변수 둘을 더했다.
#   SEC_SCHEMES=apiKey,bearer,oauth2  카드에 선언할 인증 스킴 종류(항목 1-3).
#   COMPAT=0                          v0.3 compat 라우트를 끈다(항목 1-2, 1-11).
# 아래는 스파이크 4에서 온 것이다.
#   EXT_CARD=1   확장 카드(capabilities.extended_agent_card + extended_agent_card 인자). 항목 1-4.
#   INPUT_MODE=1 본문에 'ask'가 있으면 input-required로 멈추고 같은 task_id의 다음 메시지로 재개. 항목 1-6.
#   PUSH_SEND=1  푸시 설정 저장소와 발송기를 배선(SDK 기본은 없음). 항목 1-10.
# 실행기의 나머지 동작과 카드 구성은 server3.py 그대로다.
# 바꾼 것: gRPC 트랜스포트 제거(JSON-RPC + HTTP+JSON만), 카드 URL 호스트를 CARD_HOST env로,
# 나머지(실행기, 카드 구성, v0.3 compat 라우트, 카드 라우트)는 원본 그대로.
import argparse
import os
import asyncio
import contextlib
import logging

import uvicorn

from fastapi import FastAPI

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
from a2a.server.tasks import (
    BasePushNotificationSender,
    InMemoryPushNotificationConfigStore,
)
from a2a.server.tasks.inmemory_task_store import InMemoryTaskStore
from a2a.server.tasks.task_updater import TaskUpdater
from a2a.types import (
    AgentCapabilities,
    AgentCard,
    AgentInterface,
    AgentProvider,
    AgentSkill,
    APIKeySecurityScheme,
    HTTPAuthSecurityScheme,
    OAuth2SecurityScheme,
    SecurityRequirement,
    SecurityScheme,
    Part,
    Task,
    TaskState,
    TaskStatus,
)


logger = logging.getLogger(__name__)


class SampleAgentExecutor(AgentExecutor):
    """Sample agent executor logic similar to the a2a-js sample."""

    def __init__(self) -> None:
        self.running_tasks: set[str] = set()
        # [스파이크 4] input-required로 멈춰 둔 태스크. 같은 task_id의 다음 메시지가 재개한다.
        self.awaiting_input: set[str] = set()

    async def cancel(
        self, context: RequestContext, event_queue: EventQueue
    ) -> None:
        """Cancels a task."""
        task_id = context.task_id
        if task_id in self.running_tasks:
            self.running_tasks.remove(task_id)

        updater = TaskUpdater(
            event_queue=event_queue,
            task_id=task_id or '',
            context_id=context.context_id or '',
        )
        await updater.cancel()

    async def execute(
        self, context: RequestContext, event_queue: EventQueue
    ) -> None:
        """Executes a task inline."""
        user_message = context.message
        task_id = context.task_id
        context_id = context.context_id

        if not user_message or not task_id or not context_id:
            return

        self.running_tasks.add(task_id)

        # [스파이크 4] 재개 경로: 이미 input-required로 멈춰 둔 태스크면 새 Task 이벤트를 내지 않는다.
        if task_id in self.awaiting_input:
            self.awaiting_input.discard(task_id)
            resume_updater = TaskUpdater(
                event_queue=event_queue, task_id=task_id, context_id=context_id
            )
            await resume_updater.start_work(
                message=resume_updater.new_agent_message(
                    parts=[Part(text='Resuming with your input...')]
                )
            )
            await resume_updater.add_artifact(
                parts=[Part(text=f'resumed with: {context.get_user_input()}')],
                name='response',
                last_chunk=True,
            )
            await resume_updater.complete()
            logger.info('[spike4] task %s resumed and completed', task_id)
            return

        logger.info(
            '[SampleAgentExecutor] Processing message %s for task %s (context: %s)',
            user_message.message_id,
            task_id,
            context_id,
        )

        await event_queue.enqueue_event(
            Task(
                id=task_id,
                context_id=context_id,
                status=TaskStatus(state=TaskState.TASK_STATE_SUBMITTED),
                history=[user_message],
            )
        )

        updater = TaskUpdater(
            event_queue=event_queue,
            task_id=task_id,
            context_id=context_id,
        )

        working_message = updater.new_agent_message(
            parts=[Part(text='Processing your question...')]
        )
        await updater.start_work(message=working_message)

        query = context.get_user_input()

        # [스파이크 4] input-required 분기. 본문에 'ask'가 있으면 멈추고 클라이언트 입력을 기다린다.
        if os.environ.get('INPUT_MODE', '0') == '1' and 'ask' in query.lower():
            self.awaiting_input.add(task_id)
            await updater.requires_input(
                message=updater.new_agent_message(
                    parts=[Part(text='Which environment? (spike4 input-required)')]
                )
            )
            logger.info('[spike4] task %s parked at input-required', task_id)
            return

        agent_reply_text = self._parse_input(query)
        # [스파이크 3 델타] 작업 시간을 환경변수로. 진행 중 취소를 보려는 것.
        await asyncio.sleep(float(os.environ.get('WORK_SECONDS', '1')))

        if task_id not in self.running_tasks:
            return

        await updater.add_artifact(
            parts=[Part(text=agent_reply_text)],
            name='response',
            last_chunk=True,
        )
        await updater.complete()

        logger.info(
            '[SampleAgentExecutor] Task %s finished with state: completed',
            task_id,
        )

    def _parse_input(self, query: str) -> str:
        if not query:
            return 'Hello! Please provide a message for me to respond to.'

        ql = query.lower()
        if 'hello' in ql or 'hi' in ql:
            return 'Hello World! Nice to meet you!'
        if 'how are you' in ql:
            return (
                "I'm doing great! Thanks for asking. How can I help you today?"
            )
        if 'goodbye' in ql or 'bye' in ql:
            return 'Goodbye! Have a wonderful day!'
        return f"Hello World! You said: '{query}'. Thanks for your message!"


def _scheme_names() -> list[str]:
    """[축 1] 카드에 declare할 스킴 이름 목록. 기본은 스파이크와 같은 apiKey 하나."""
    raw = os.environ.get('SEC_SCHEMES', 'apiKey')
    return [s.strip() for s in raw.split(',') if s.strip()]


def _build_schemes() -> dict:
    """[축 1] 항목 1-3. 스킴 종류를 바꿔도 강제가 붙지 않는지 보려는 것이라
    서버 코드에는 검증을 넣지 않는다. 선언만 만든다."""
    out = {}
    for name in _scheme_names():
        if name == 'apiKey':
            out[name] = SecurityScheme(
                api_key_security_scheme=APIKeySecurityScheme(
                    name='X-API-Key', location='header',
                    description='axis1: declared, not enforced by the sample server',
                )
            )
        elif name == 'bearer':
            out[name] = SecurityScheme(
                http_auth_security_scheme=HTTPAuthSecurityScheme(
                    scheme='bearer', bearer_format='JWT',
                    description='axis1: declared, not enforced by the sample server',
                )
            )
        elif name == 'oauth2':
            out[name] = SecurityScheme(
                oauth2_security_scheme=OAuth2SecurityScheme(
                    description='axis1: declared, not enforced by the sample server',
                    oauth2_metadata_url='https://example.com/.well-known/oauth-authorization-server',
                )
            )
        else:
            raise ValueError(f'unknown scheme name: {name}')
    return out


async def serve(
    host: str = '127.0.0.1',
    port: int = 41241,
) -> None:
    import os
    card_host = os.environ.get('CARD_HOST', f'{host}:{port}')
    """Run the Sample Agent server with mounted JSON-RPC, HTTP+JSON and gRPC transports."""
    agent_card = AgentCard(
        name='Sample Agent',
        description='A sample agent to test the stream functionality.',
        provider=AgentProvider(
            organization='A2A Samples', url='https://example.com'
        ),
        version='1.0.0',
        capabilities=AgentCapabilities(
            streaming=True,
            # [스파이크 3 델타] 푸시 알림을 선언한다. 발송기는 SDK 기본(없음) 그대로 둔다.
            push_notifications=os.environ.get('PUSH_CAP', '0') == '1',
            # [스파이크 4] 확장 카드 선언. 실제 카드는 아래 handler의 extended_agent_card로 준다.
            extended_agent_card=os.environ.get('EXT_CARD', '0') == '1',
        ),
        # [스파이크 2 델타] 카드에 인증 스킴을 선언한다. 서버 코드에는 검증이 없다.
        # 선언과 강제가 갈리는지 보려는 것이므로 실행기는 원본 그대로 둔다.
        security_schemes=_build_schemes(),
        security_requirements=[
            SecurityRequirement(schemes={k: {} for k in _scheme_names()})
        ],
        default_input_modes=['text'],
        default_output_modes=['text', 'task-status'],
        skills=[
            AgentSkill(
                id='sample_agent',
                name='Sample Agent',
                description='Say hi.',
                tags=['sample'],
                examples=['hi'],
                input_modes=['text'],
                output_modes=['text', 'task-status'],
            )
        ],
        supported_interfaces=[
            AgentInterface(
                protocol_binding='JSONRPC',
                protocol_version='1.0',
                url=f'http://{card_host}/a2a/jsonrpc',
            ),
            AgentInterface(
                protocol_binding='JSONRPC',
                protocol_version='0.3',
                url=f'http://{card_host}/a2a/jsonrpc',
            ),
            AgentInterface(
                protocol_binding='HTTP+JSON',
                protocol_version='1.0',
                url=f'http://{card_host}/a2a/rest',
            ),
            AgentInterface(
                protocol_binding='HTTP+JSON',
                protocol_version='0.3',
                url=f'http://{card_host}/a2a/rest',
            ),
        ],
    )

    task_store = InMemoryTaskStore()

    # [스파이크 4] 확장 카드: 공개 카드에 없는 스킬 하나를 더 단 사본을 준비한다.
    extended_card = None
    if os.environ.get('EXT_CARD', '0') == '1':
        extended_card = AgentCard()
        extended_card.CopyFrom(agent_card)
        extended_card.description = 'Extended card (spike4): visible only via GetExtendedAgentCard'
        extended_card.skills.append(
            AgentSkill(
                id='secret_skill',
                name='Secret Skill',
                description='spike4: present only in the extended card',
                tags=['spike4'],
                examples=['secret'],
                input_modes=['text'],
                output_modes=['text'],
            )
        )

    # [스파이크 4] 푸시 발송기 배선. SDK 기본에는 저장소도 발송기도 없어 설정 자체가 거절된다.
    push_config_store = None
    push_sender = None
    push_client = None
    if os.environ.get('PUSH_SEND', '0') == '1':
        import httpx

        push_client = httpx.AsyncClient(timeout=10.0)
        push_config_store = InMemoryPushNotificationConfigStore()
        push_sender = BasePushNotificationSender(
            httpx_client=push_client, config_store=push_config_store
        )

    request_handler = DefaultRequestHandler(
        agent_executor=SampleAgentExecutor(),
        task_store=task_store,
        agent_card=agent_card,
        push_config_store=push_config_store,
        push_sender=push_sender,
        extended_agent_card=extended_card,
    )

    # [축 1] 항목 1-2와 1-11. compat을 끈 카드도 병기인지, 끄면 어느 경로가 사라지는지 본다.
    compat = os.environ.get('COMPAT', '1') == '1'
    rest_routes = create_rest_routes(
        request_handler=request_handler,
        path_prefix='/a2a/rest',
        enable_v0_3_compat=compat,
    )
    jsonrpc_routes = create_jsonrpc_routes(
        request_handler=request_handler,
        rpc_url='/a2a/jsonrpc',
        enable_v0_3_compat=compat,
    )
    agent_card_routes = create_agent_card_routes(
        agent_card=agent_card,
    )
    app = FastAPI()
    add_a2a_routes_to_fastapi(
        app,
        agent_card_routes=agent_card_routes,
        jsonrpc_routes=jsonrpc_routes,
        rest_routes=rest_routes,
    )

    config = uvicorn.Config(app, host=host, port=port)
    uvicorn_server = uvicorn.Server(config)

    logger.info('Starting Sample Agent servers:')
    logger.info(' - HTTP on http://%s:%s', host, port)
    logger.info(
        'Agent Card available at http://%s:%s/.well-known/agent-card.json',
        host,
        port,
    )

    await uvicorn_server.serve()


if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    parser = argparse.ArgumentParser(description='Sample A2A agent server')
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=41241)
    args = parser.parse_args()
    with contextlib.suppress(KeyboardInterrupt):
        asyncio.run(
            serve(host=args.host, port=args.port)
        )
