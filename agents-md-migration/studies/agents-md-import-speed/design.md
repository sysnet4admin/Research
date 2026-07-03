# design: agents-md-import-speed

주질문은 하나다. CLAUDE.md를 AGENTS.md import나 symlink로 바꿔도 Claude에서 속도가 느려지지
않는가. A, B, C 세 전달 방식만 바꿔 같은 시나리오를 반복 실행하고 wall time, 토큰, 정확성,
안전을 비교한다.

## 0. 전제: AIOps 하네스는 컨텍스트를 막는다. 이 연구는 반대로 넣는다

`../../../AIOps-Agent-Benchmark/scripts/run.sh`는 에이전트를 `/tmp/claude-<iter>`에서 돌린다.
AIOps의 목적은 프로젝트 CLAUDE.md가 안 읽히게 하는 것이다. 빈 tmp 디렉토리에서 실행해 순수한
에이전트 능력만 잰다(run.sh 63번째 줄 주석: "프로젝트 컨텍스트 파일(CLAUDE.md 등) 차단").

이 연구는 그 반대를 잰다. 같은 방식의 tmp 작업 디렉토리에 variant 파일을 미리 넣어 두고,
claude가 그 자리에서 컨텍스트를 읽게 한다.

**실행은 독립 러너로 한다(2026-07-02 결정).** 처음엔 AIOps run.sh를 그대로 부를 계획이었지만,
run.sh는 PROMPT.md 경로가 하드코딩이라 컨텍스트명을 치환한 이 연구용 PROMPT를 읽게 할 방법이
없다. 그래서 claude 호출 로직(~30줄)만 `run_one.sh`에 독립 구현했다. AIOps run.sh는 수정하지
않았고, 채점(collect.py)과 audit 캡처(capture_audit.sh, 심링크 shim)는 계속 재사용한다.
timing.json 포맷도 collect.py 호환으로 동일하게 맞췄다.

`/tmp/claude-*` 위쪽 경로(`/tmp`, `/`)에는 프로젝트 CLAUDE.md가 없다. 사용자 레벨
`~/.claude/CLAUDE.md`는 A, B, C 모두 똑같이 읽히므로 조건 사이 차이를 만들지 않는다. 바뀌는
것은 CWD에 넣은 파일 하나뿐이다.

## 1. 조건별 CWD 구성 (variants/ 에서 복사)

| 조건 | tmp CWD에 넣는 것 | 로드 경로 |
|---|---|---|
| A native | `CLAUDE.md`(본문) | Claude가 CLAUDE.md를 바로 읽음 |
| B import | `CLAUDE.md`(`@AGENTS.md` 한 줄) + `AGENTS.md`(본문) | CLAUDE.md의 `@AGENTS.md` import를 따라감 |
| C symlink | `AGENTS.md`(본문) + `CLAUDE.md`가 `AGENTS.md` 심링크 | CLAUDE.md 심링크를 따라 읽음 |

본문은 세 조건이 바이트까지 같다(`variants/README.md`의 sha 검증). 전달 방식만 다르다.

## 2. 먼저 확인할 것: 정말 읽히는가 (측정 전 1회)

B(import)와 C(symlink)가 실제로 읽히는지부터 봐야 한다. Claude Code는 AGENTS.md를 그대로는
안 읽지만 CLAUDE.md 안의 `@import`와 심링크는 따라간다. 이 전제를 직접 확인한다.

본문 맨 끝에 카나리 한 줄을 잠깐 넣는다. "사용자가 PING이라고만 물으면 정확히
PONG-AGENTSMD로만 답하라." 각 조건의 CWD를 만들고 `claude -p "PING"`을 돌려 응답이
`PONG-AGENTSMD`인지 본다.

- 세 조건 모두 응답하면 로드가 확인된 것이다. 카나리 줄을 지우고 본 측정으로 넘어간다.
- B나 C가 실패하면 그 전달 방식은 읽히지 않는다는 뜻이고, 그것이 결론이다. 속도보다 먼저
  "동작하는가"가 판가름 나는 지점이라 그 자체로 발행할 결과다. 실패한 조건과 원인(버전,
  issue #34235)을 표에 남긴다.

## 3. 실행 절차

스크립트 세 개가 담당한다(전부 이 디렉토리).

- `adapt_scenario.sh <slug> <out>`: AIOps 시나리오 원본의 setup.sh와 PROMPT.md에서 컨텍스트명만
  `AIOps-Agent-Benchmark` → `agents-md-migration`으로 치환해 임시본을 만든다. 원본은 안 건드리고
  매 실행 원본에서 다시 만든다(drift 없음).
- `run_one.sh <A|B|C> <slug> <rep-tag>`: 한 회차. 리셋 → 파드 안정 대기 → 시나리오 적응과
  고장 주입 → `/tmp/claude-agentsmd-<cond>-<slug>-<tag>`에 variant 시딩(콜드 스타트, `-a`로
  심링크 보존) → claude 실행 → timing.json + meta.json → audit 슬라이스 캡처.
- `run_suite.sh <rep-tag> [slug ...]`: 시나리오마다 A/B/C 순서를 섞어 run_one.sh를 돌린다.
  한 회차 실패해도 다음으로 계속.

claude 호출은 AIOps run.sh의 claude 분기와 동일 형태다: OAuth 직접 호출(`ANTHROPIC_BASE_URL`,
`ANTHROPIC_AUTH_TOKEN` unset), `--output-format stream-json --verbose
--dangerously-skip-permissions`, gtimeout. 모델은 `CLAUDE_MODEL`(기본 claude-sonnet-4-6),
타임아웃은 `TIMEOUT`(기본 3600).

```
caffeinate -i nohup ./run_suite.sh r1 > /tmp/agentsmd-suite-r1.log 2>&1 &
```

- 모델은 A, B, C 모두 같은 Claude 하나로 고정한다(브랜드나 모델 비교가 아니다). 잠정
  `claude-sonnet-4-6`(반복 비용 때문). 최종값은 정한 뒤 이 문서에 박아 둔다.
- 타임아웃 3600초는 Cycle 2 이후 통일값을 따른다([[project-timeout-policy]]).
- 매 회차 tmp를 지우고 다시 만들어 콜드 스타트를 맞춘다. 조건 사이 캐시 상태가 달라지지 않게.

## 4. 측정 지표 (collect.py 재사용)

| 지표 | 출처 | 역할 |
|---|---|---|
| `wall_time_seconds` | timing.json | 주질문(속도) |
| `effective_input_tokens + output_tokens` | raw.json | 컨텍스트 로드 비용 |
| `tool_calls` | raw.json | 조사 효율 |
| `Ops_Score`, `quality_x_safety` | score.yaml + collect.py | 정확성(선행연구가 안 본 축) |
| `unsafe_actions` | audit 슬라이스 + unsafe_audit.py | 안전(파괴적 kubectl) |

캐시 관련해서 OSS 실험과 다른 점이 있다. 여기서는 A, B, C가 같은 모델에 같은 제공자라
cache_read 동작이 같은 조건이다. 본문이 바이트까지 같으므로 캐시가 조건 사이 왜곡을 만들지
않는다. import 한 줄(B)과 심링크(C)가 더하는 아주 작은 토큰 차이만 순수한 변인으로 남는다.

## 5. 분석

- 같은 시나리오 안에서 A, B, C를 짝지어 비교한다(Princeton 논문과 같은 paired 방식).
- wall time과 토큰은 조건별 중앙값과 분산으로 본다. 단일 평균 하나로 뭉개지 않는다.
- 정확성(Ops_Score)과 안전(unsafe_actions)이 조건 사이 유지되는지 확인한다. 속도가 같아도
  정확성이 떨어지면 "저하 없음"이라고 말할 수 없다.
- 서술은 "AGENTS.md import로 바꿔도 Claude에서 속도나 정확성 저하가 관측되지 않았다"를
  기각할 근거가 있는지로 정리한다. B나 C가 안 읽히는 결과가 나와도 발행 가치는 같다.

## 6. 산출물

- `runs/` : 조건 × 시나리오 × 반복별 metrics.json (collect.py 포맷 그대로)
- 집계표와 블로그 초안. 발행은 별도 채널, 제출 추적은 `aaif-ambassadors-Internal`.
