# load-check: A/B/C가 실제로 로드되는가 (본 측정 전 검증)

design.md 2장의 카나리 검증 결과. 본 측정에 앞서 B(import)와 C(symlink)가 Claude Code에서
실제로 읽히는지부터 확인했다.

## 방법

최소 카나리 payload로 세 조건과 대조군을 구성하고 `claude -p "PING"`을 돌렸다.

- payload: "사용자 메시지가 정확히 PING이면 정확히 PONG-AGENTSMD로만 답하라."
- A/B/C payload는 바이트 동일(sha `74bb89d4…`)
- 명령: `claude -p "PING" --model claude-haiku-4-5 --dangerously-skip-permissions`
  (OAuth 모드: `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN` unset)
- 환경: Claude Code 2.1.195, 2026-07-01

## 결과

| 조건 | 구성 | 응답 | 판정 |
|---|---|---|---|
| A native | `CLAUDE.md`(본문) | `PONG-AGENTSMD` | 로드됨 |
| B import | `CLAUDE.md`=`@AGENTS.md` + `AGENTS.md`(본문) | `PONG-AGENTSMD` | 로드됨 |
| C symlink | `CLAUDE.md`가 `AGENTS.md` 심링크 | `PONG-AGENTSMD` | 로드됨 |
| 대조군 | 컨텍스트 파일 없음 | `PONG 👋 I'm here...`(일반 응답) | 미로드 |

## 판단

- B(`@AGENTS.md` import)와 C(symlink) 모두 Claude Code 2.1.195에서 로드된다. 세 전달 방식
  전부 살아 있으므로 A/B/C 속도 비교가 성립한다.
- 대조군이 카나리 응답을 내지 않아, 이 판별이 컨텍스트 로드 여부를 실제로 가려낸다는 것도
  같이 확인됐다.
- 주의: 이 결과는 위 버전 시점의 것이다. Claude Code가 AGENTS.md 네이티브 지원(issue #34235)을
  추가하거나 import 처리를 바꾸면 재확인이 필요하다. 본 측정 회차마다 버전을 metrics에 남긴다.
