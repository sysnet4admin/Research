# 안전 어포던스 실측 (tools/list 직접 계수)

측정 시각: 2026-08-20 08:52:16. LLM 미사용, MCP 서버에 JSON-RPC 직접 호출.

read-only를 켰을 때 **목록 자체가 줄어드는가**를 본다. 줄지 않으면 도구 정의가
그대로 컨텍스트에 실리므로, 안전 모드를 켜도 토큰 비용은 한 푼도 줄지 않는다.

| 서버 | 안전 설계 | 기본 | read-only | 감소 | 감소율 |
|---|---|---|---|---|---|
| containers | 어노테이션 필터 | 20 | 14 | 6 | 30% |
| reza | 등록 시점 차단 | 22 | 13 | 9 | 41% |
| flux159 | 하드코딩 목록 | 23 | 8 | 15 | 65% |
| ro-only | 구조적(쓰기 경로 없음) | 10 | 10 | 0 | 0% |
| azure-k8s | access-level | 1 | 1 | 0 | 0% |
| rohitg00 | 호출 시점만 차단 | 275 | 275 | 0 | 0% |

## 판독

**목록이 줄어드는 설계 (3종)**
- containers 20 → 14 (30% 감소). 어노테이션(ReadOnlyHint)으로 걸러 노출 자체를 줄인다.
  사라지는 6개는 `pods_delete`, `pods_exec`, `pods_run`, `resources_create_or_update`, `resources_delete`, `resources_scale`다(2026-09-09 이름 확인).
- reza 22 → 13 (41% 감소). 쓰기 도구를 아예 등록하지 않는다. 감소율 최대.
- flux159 23 → 8 (65% 감소). `ALLOW_ONLY_READONLY_TOOLS=true`가 가장 공격적으로 줄인다.
  단 이 옵션은 최근 추가분이고 기존 `ALLOW_ONLY_NON_DESTRUCTIVE_TOOLS`는 18개를 남기며
  그 안에 `exec_in_pod`가 살아 있다(재조사 확인).

**목록이 그대로인 설계 (3종)**
- rohitg00 275 → **275 (0% 감소)**. read-only를 켜도 도구 정의가 전부 노출된다.
  호출하면 차단되므로 안전은 지켜지지만 입력 토큰 298K는 그대로 나간다.
  본 측정에서 이 서버의 토큰당 성과가 최하(containers의 1/4.3)인 이유가 여기 있다.
- ro-only 10 → 10. 애초에 쓰기 경로가 없으므로 감소가 없는 것이 정상이다.
- azure-k8s 1 → 1. 도구가 `call_kubectl` 하나뿐이라 목록으로 구분할 수 없고
  명령 문자열을 실행 시점에 검증한다. README가 access-level은 보안 경계가 아니라고 명시한다.

## 함의

안전 모드의 비용 효과가 설계에 따라 정반대다. 등록·필터 계열(reza, containers,
flux159)은 안전과 토큰 절약을 함께 얻지만 호출 차단 계열(rohitg00)은 안전만 얻고
비용은 그대로다. 서버를 고를 때 'read-only를 지원하는가'가 아니라 **'어떻게 구현했는가'**
를 봐야 한다는 근거다.

## 방법 주기

초기 시도가 6종 중 4종에서 실패했다. 원인 둘. ① 셸의 `NODE_OPTIONS`가 존재하지 않는
preload 스크립트를 걸어 node 기동 자체가 실패(env에서 제거로 해결). ② 서버가 stdin
종료 직후 프로세스를 닫아 `subprocess.run(input=)`으로는 응답을 못 받음(파이프 + sleep
유지 후 파일 리다이렉트로 해결). 도구 이름 원자료는 `SAFETY_PROBE.json`.

**도구 이름 보강 (2026-09-09, M4).** containers와 rohitg00은 계수만 있고 이름이
비어 있어서 다시 받았다. 두 서버 모두 개수는 원측정과 같다(20/14, 275/275).
그 과정에서 두 가지를 더 확인했다. ① 원인 ②의 방아쇠는 `subprocess.run(input=)`이
아니라 **stdin을 닫는 것 자체**다. 파이프를 열어 둔 채 응답을 읽으면 containers도
정상 응답하며 `harness/safety_probe.py`를 그 방식으로 바꿨다. ② rohitg00은 지금
같은 명령으로는 기동하지 않는다. uvx가 `mcp` 2.x를 끌어오는데 이 패키지는 v1
API(`mcp.server.fastmcp`)를 쓰기 때문이다. 재현하려면
`uvx --from kubectl-mcp-server --with 'mcp<2' kubectl-mcp-serve serve --transport stdio`로
의존성을 고정해야 한다.
