# RESULTS: agents-md-import-speed

주질문: CLAUDE.md를 AGENTS.md import나 symlink로 바꾸면 Claude에서 속도나 비용이 늘어나는가.
답: 관측되지 않았다. 속도와 과금 토큰 양쪽 다 체계적 저하가 없다. 아래는 근거다.

측정 환경: 전용 2노드 클러스터(K8s v1.36.2, 컨텍스트 `agents-md-migration`), Claude Code 2.1.198,
2026-07-02. 시나리오는 AIOps 벤치마크 것을 컨텍스트명만 치환해 재사용. 채점 파서(collect.py)와
audit 캡처는 AIOps 하네스 재사용, 에이전트 실행만 독립 러너(run_one.sh).

## 조건

세 조건의 본문(payload)은 바이트까지 동일하다. 전달 방식만 다르다(sha 검증, variants/README.md).

- A native: `CLAUDE.md`(본문)
- B import: `CLAUDE.md`(`@AGENTS.md` 한 줄) + `AGENTS.md`(본문)
- C symlink: `AGENTS.md`(본문) + `CLAUDE.md`가 `AGENTS.md` 심링크

## 0단계: 정말 로드되는가 (load-check)

본 측정 전에 세 방식이 실제로 읽히는지부터 확인했다(load-check.md). 카나리 payload로
`claude -p "PING"` 실행 결과, A/B/C 모두 `PONG-AGENTSMD` 응답, 대조군(파일 없음)만 미응답.
Claude Code가 AGENTS.md를 네이티브로는 안 읽어도(issue #34235) `@import`와 심링크는 따라간다는
전제가 확인됐다.

## 1단계: r1 (10 시나리오 x A/B/C, sonnet-4-6, 각 1회)

30회차 전부 rc=0. wall time을 시나리오별로 짝지어 보면 A 대비 B/C 편차의 부호가 시나리오마다
뒤섞인다(B가 4번 빠르고 3번 느림). 전달 방식이 원인이라면 부호가 일관돼야 하는데 그렇지 않다.
큰 편차(005-pvc B +86%)는 tool call 수가 늘어난 것과 같이 움직여, 컨텍스트 로드가 아니라
에이전트 풀이 경로 차이다. r1은 파이프라인 정확성과 방향성(저하 없음)까지 보였고, 어려운
시나리오의 분산 때문에 모델 스윕은 저분산 시나리오(001~004)에 집중했다.

## 2단계: 모델 스윕 (001~004 x A/B/C x 4모델 x N=3)

144회차 전부 rc=0. 모델별 36회차 균등. 조건별 셔플로 시간대 드리프트 분산.

### 비용 관련 지표: cache_creation (일회성 컨텍스트 로드 토큰)

전달 방식이 과금되는 로드를 부풀렸는지 가장 정확히 보는 지표. import/symlink가 로드를 키웠다면
B가 A보다 커야 한다. 결과는 반대다.

| 모델 | A | B vs A | C vs A |
|---|---|---|---|
| Haiku 4.5 | 22,049 | -3% | +1% |
| Sonnet 4.6 | 14,357 | -3% | -1% |
| Opus 4.8 | 15,542 | -4% | -1% |
| Fable 5 | 16,357 | -3% | -1% |

B가 네 모델 전부에서 일관되게 3~4% 낮다(노이즈면 부호가 섞여야 한다). import는 로드 토큰을
늘리지 않고 오히려 약간 줄인다(Claude Code가 import를 native 인라인과 다르게 렌더링하는 것으로
보임). symlink는 native와 ±1% 안, 사실상 동일.

uncached input 토큰도 조건 간 0~-4%로 평평하다.

### 속도와 실행 지표

| 지표 | 관측 |
|---|---|
| wall time | 편차가 모델마다 부호 혼재(Haiku C +35%, Sonnet B +29%, Opus B -9%). 토큰 편차와 어긋남(Haiku C는 시간 +35%인데 토큰 +3%). 실행 경로 분산이 원인 |
| effective input(합계) | -7% ~ +7%, 부호 혼재. cache_read가 지배해 실행 경로 반영 |
| output 토큰 | ±15% 이내, 부호 혼재 |
| tool calls | ±8% 이내, 부호 혼재 |

## 결론

- 속도: import(B), symlink(C) 모두 native(A) 대비 체계적 저하 없음. wall time 변동은 전달 방식이
  아니라 LLM 실행 경로 분산에서 온다(토큰 편차와 어긋나고 부호가 조건과 무관).
- 비용(토큰): 일회성 로드 토큰이 import/symlink에서 늘지 않는다. import는 4개 티어 전부 약 3%
  낮다. 실제 달러 비용을 좌우하는 턴 수와 output은 조건과 무관한 실행 분산이라 반복하면 0에 수렴.
- 일반화: Haiku부터 Fable(Mythos급 최상위)까지 4개 티어에서 같은 결론. A/B/C 차이는 Claude Code가
  모델 호출 전에 해소하므로 원리상 모델 무관이고, 실측도 그대로다.

즉 AIOps의 CLAUDE.md를 AGENTS.md import 형태로 옮겨도 속도나 과금 토큰에 페널티가 없다.

## 재현

```
# 클러스터: test-cluster/up.sh -> enable-audit.sh -> snapshot.sh baseline
# load-check: design.md 2장
# r1:    ./run_suite.sh r1
# 스윕:  REPS=3 nohup caffeinate -i bash run_model_sweep.sh > /tmp/agentsmd-sweep.log 2>&1 &
# 집계:  python3 report_sweep.py     (모델 x 조건)
#        python3 aggregate.py        (전체 회차 CSV)
```

## 한계와 다음

- 정확성(Ops_Score)과 안전(unsafe_actions)은 아직 채점 안 함. wall time과 토큰만 자동 수집됐다.
  cache_creation과 속도로 주질문(저하 여부)은 답했지만, "정확성도 유지되는가"는 score.yaml 채점이
  더 필요하다.
- 스윕은 저분산 시나리오(001~004)에 한정. 어려운 시나리오(005~010)는 r1 sonnet 1회뿐이라 분산이
  크다. 결론(전달 방식 무관)은 저분산 구간에서 가장 깨끗하게 확인됐다.
