# RESULTS: agents-md-import-speed

주질문: CLAUDE.md를 AGENTS.md import나 symlink로 바꾸면 Claude에서 속도나 비용이 늘어나는가.
답: 관측되지 않았다. 속도와 과금 토큰 어느 쪽에도 전달 방식에서 오는 체계적 페널티가 없다.
아래는 근거다.

측정 환경: 전용 2노드 클러스터(K8s v1.36.2, 컨텍스트 `agents-md-migration`). 시나리오는 AIOps
벤치마크 것을 컨텍스트명만 치환해 재사용. 채점 파서(collect.py)와 audit 캡처는 AIOps 하네스
재사용, 에이전트 실행만 독립 러너(run_one.sh).

측정 시점과 버전: Haiku 4.5, Sonnet 4.6, Opus 4.8, Fable 5 스윕은 2026-07-02(Claude Code
2.1.198), Sonnet 5 스윕과 1차 전체 통과는 2026-07-03~04(Claude Code 2.1.199).

## 조건

세 조건의 본문(payload)은 바이트까지 동일하다. 전달 방식만 다르다(sha 검증, variants/README.md).

- A native: `CLAUDE.md`(본문)
- B import: `CLAUDE.md`(`@AGENTS.md` 한 줄) + `AGENTS.md`(본문)
- C symlink: `AGENTS.md`(본문) + `CLAUDE.md`가 `AGENTS.md` 심볼릭 링크

**C는 대조군 역할을 한다.** 심볼릭 링크는 경로를 여는 순간 파일시스템이 해석하므로 Claude
Code 입장에서는 native와 완전히 같은 읽기다. 따라서 C에서 관측되는 편차는 전부 실행 노이즈이고,
B의 편차가 C와 같은 크기라면 import 인다이렉션의 고유 비용은 없다는 뜻이 된다.

## 0단계: 정말 로드되는가 (load-check)

본 측정 전에 세 방식이 실제로 읽히는지부터 확인했다(load-check.md). 확인용 문장을 심은
payload로 `claude -p "PING"` 실행 결과, A/B/C 모두 지정된 응답을 냈고 대조군(파일 없음)만
응답하지 않았다. Claude Code가 AGENTS.md를 네이티브로는 안 읽어도(issue #34235) `@import`와
심볼릭 링크는 따라간다는 전제가 확인됐다.

## 1단계: 전체 통과 (10 시나리오 x A/B/C)

Sonnet 5로 10개 시나리오 전체를 조건당 한 번씩 돌렸다(30회, 태그 r2). 같은 구성을 Sonnet
4.6으로 돌린 회차(30회, 태그 r1)도 보존돼 있다. 결과 양상은 두 모델이 같다: 쉬운
시나리오에서는 세 조건이 노이즈 범위 안이고, 어려운 시나리오의 큰 편차는 tool call 수와 같이
움직이는 실행 경로 차이다. r2 중 1회(C-008)가 API 500 서버 오류로 실패해 즉시 재실행했다
(인프라 실패 재실행 정책, 에이전트 능력과 무관).

## 2단계: 모델 스윕 (001~004 x A/B/C x 5모델 x N=3 = 180회)

편차가 작은 4개 시나리오에서 모델 5종을 3회씩 반복했다. 조건 순서는 회차마다 셔플.

### cache write 토큰 (조건별 중앙값, 셀당 n=12)

| 모델 | A (native) | B (import) vs A | C (symlink, 대조군) vs A |
|---|---|---|---|
| Haiku 4.5 | 22,049 | -3% | +1% |
| Sonnet 4.6 | 14,357 | -3% | -1% |
| Sonnet 5 | 17,252 | +6% | +6% |
| Opus 4.8 | 15,542 | -4% | -1% |
| Fable 5 | 16,357 | -3% | -1% |

### wall time (조건별 중앙값, 초)

| 모델 | A | B vs A | C vs A |
|---|---|---|---|
| Haiku 4.5 | 22.1 | +3% | +35% |
| Sonnet 4.6 | 40.1 | +29% | -6% |
| Sonnet 5 | 49.7 | +8% | -4% |
| Opus 4.8 | 76.2 | -9% | +17% |
| Fable 5 | 79.2 | +14% | -3% |

## 해석

- **전달 방식 페널티 없음이 주 결론이고, 5모델에서 유지된다.** 어느 지표에서도 B가 대조군
  C를 체계적으로 웃돌지 않는다. wall time 편차는 부호가 모델마다 갈리고 토큰 편차와 어긋난다
  (실행 경로 분산의 특징).
- **"import가 항상 3~4% 가볍다"는 초기 관찰은 일반화되지 않는다.** 4개 모델(2.1.198 측정)에서
  B가 일관되게 3~4% 낮았지만, Sonnet 5(2.1.199)에서는 B +6%로 방향이 뒤집혔다. 결정적으로
  같은 회차 묶음에서 **대조군 C도 똑같이 +6%**였다. C는 메커니즘상 native와 달라질 수 없으므로,
  이 +6%는 전달 방식이 아니라 실행 노이즈다. 따라서 cache write의 조건 간 편차는 ±6% 안이고,
  방향은 모델과 회차에 따라 갈리며, 전달 방식에 따른 체계적 비용 신호는 없다.
- **cache write 지표의 한계 두 가지를 확인했다.** (1) 이 값은 세션 시작 로드만이 아니라 턴마다
  새로 캐시에 쓰는 양의 합산이라, 풀이가 길어지면 커진다(Sonnet 5의 B/C는 output 토큰도
  +20% 안팎으로 같이 늘었다). (2) 인접 회차와 조립 컨텍스트가 동일하면 API 프롬프트 캐시
  TTL(5분) 안에서 적중해 cache write가 급감할 수 있다(003 시나리오 A 1회에서 1,901로 관측).
  클러스터는 회차마다 스냅샷 복원으로 콜드 스타트지만, API 레벨 캐시까지 차단되지는 않는다.

## 결론

- 속도: import(B), symlink(C) 모두 native(A) 대비 체계적 저하 없음. 5개 모델 티어에서 동일.
- 비용(토큰): 전달 방식에 따른 체계적 증가 없음. 조건 간 편차(±6%)는 대조군과 같이 움직이는
  실행 노이즈다.
- 일반화: Haiku부터 Fable(Mythos급 최상위)까지, 그리고 구세대(4.x)와 신세대(5) Sonnet
  양쪽에서 같은 결론. A/B/C 차이는 Claude Code가 모델 호출 전에 해소하므로 원리상 모델
  무관이고, 실측도 그대로다.

즉 AIOps의 CLAUDE.md를 AGENTS.md import 형태로 옮겨도 속도나 과금 토큰에 페널티가 없다.

## 재현

```
# 클러스터: test-cluster/up.sh -> enable-audit.sh -> snapshot.sh baseline
# load-check: design.md 2장
# 1차 통과:  CLAUDE_MODEL=claude-sonnet-5 ./run_suite.sh r2
# 스윕:      REPS=3 nohup caffeinate -i bash run_model_sweep.sh > /tmp/agentsmd-sweep.log 2>&1 &
#            (Sonnet 5 추가분은 sonnet5_rerun.sh)
# 집계:      python3 report_sweep.py     (모델 x 조건)
#            python3 aggregate.py        (전체 회차 CSV)
```

## 한계와 다음

- 정확성(Ops_Score)과 안전(unsafe_actions)은 채점하지 않았다. wall time과 토큰만 자동 수집.
  audit 슬라이스는 회차마다 캡처돼 있어 나중에 채점을 붙일 수 있다.
- 스윕은 저분산 시나리오(001~004)만 다룬다. 어려운 시나리오(005~010)는 1단계에서 조건당
  1회라 분산이 크다.
- cache write를 "세션 시작 로드"만으로 분리하려면 result 합산이 아니라 첫 턴 usage를 봐야
  한다. 차기 측정에서 지표를 분리할 가치가 있다.
