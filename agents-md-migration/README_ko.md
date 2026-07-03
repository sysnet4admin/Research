# AGENTS.md 마이그레이션

[English](README.md)

프로젝트 컨텍스트 파일을 `CLAUDE.md`에서 **AGENTS.md**로 옮기면 Claude Code가 느려지거나 비용이 늘어날까?

이 의문에서 연구가 시작되었습니다.

[AGENTS.md](https://agents.md/)는 AAIF(Agentic AI Foundation, Linux Foundation)가 관리하는 개방형 컨텍스트 파일 형식으로, 30개가 넘는 코딩 에이전트가 읽습니다. 그런데 Claude Code는 이 파일을 그대로는 읽지 않아서([issue #34235](https://github.com/anthropics/claude-code/issues/34235)), 마이그레이션하려면 둘 중 하나가 필요합니다. `CLAUDE.md` 안에 `@AGENTS.md` import 한 줄을 두거나, `CLAUDE.md`를 `AGENTS.md`로 가는 심볼릭 링크(symlink)로 바꾸는 것입니다. 이 연구는 그 두 우회로에 실제 비용이 있는지를 쿠버네티스 장애 대응 작업 위에서 측정했습니다.

> **이 README는 결과, 환경, 재현 방법을 모아두는 레퍼런스 시트입니다.** 작성 동기와 결과 해석은 [블로그 글](https://kuberneteslab.dev/ko/blog/agents-md-migration/)에서 다룹니다.
>
> 시나리오, 채점 파서, audit 캡처는 같이 공개된 [AIOps Agent Benchmark](https://github.com/sysnet4admin/Research/tree/main/AIOps-Agent-Benchmark)를 재사용합니다. 이 연구는 Claude Code 하나만 측정하며, 벤더 간 비교가 아닙니다.

## 요약

- **세 가지 전달 방식 모두 실제로 읽힙니다.** 카나리 검증으로 `@AGENTS.md` import와 심볼릭 링크 둘 다 Claude Code가 따라가는 것을 확인했습니다(컨텍스트 없는 대조군만 카나리에 응답하지 않았습니다).
- **속도 저하가 없습니다.** 5개 모델 구성(Haiku 4.5, Sonnet 4.6, Sonnet 5, Opus 4.8, Fable 5) 전부에서 wall time 편차의 부호가 조건마다 뒤바뀌고 토큰 편차와도 어긋납니다. 이는 컨텍스트 로드 오버헤드가 아니라 LLM 실행 편차의 특징입니다.
- **토큰 비용 페널티가 없습니다.** 조건 간 cache write 토큰 편차는 ±6% 안이고, 메커니즘상 native와 동일해 대조군 역할을 하는 심볼릭 링크와 같이 움직입니다. 4개 모델에서는 import가 native보다 3~4% 낮았고, Sonnet 5에서는 import와 심볼릭 링크가 똑같이 6% 높았습니다. 대조군과 함께 움직였다는 것은 이 편차가 전달 비용이 아니라 실행 편차라는 뜻입니다.

## 조건

세 조건의 본문(payload)은 체크섬으로 검증한 바이트 동일 문서입니다. 전달 방식만 다릅니다.

| 조건 | 에이전트 작업 디렉토리의 파일 | Claude Code가 읽는 경로 |
|---|---|---|
| **A** native | `CLAUDE.md`(본문) | `CLAUDE.md`를 바로 읽음 |
| **B** import | `CLAUDE.md`(`@AGENTS.md` 한 줄) + `AGENTS.md`(본문) | `@AGENTS.md` import를 따라감 |
| **C** symlink | `AGENTS.md`(본문) + 그리로 가는 `CLAUDE.md` 심볼릭 링크 | `CLAUDE.md` 경로를 여는 순간 OS가 링크를 풀어 `AGENTS.md` 내용을 돌려줌 |

C에서 Claude Code가 따로 하는 일은 없습니다. 링크 해석은 파일을 여는 시점에 파일시스템이 처리하므로, Claude Code 입장에서는 native와 같은 읽기입니다. 그래서 C는 실험에 내장된 대조군이 됩니다. C가 A와 벌어지는 만큼은 측정 노이즈이고, B의 편차가 C를 넘어설 때만 import 고유의 비용이 있다는 뜻이 됩니다.

본문은 합성 문서가 아니라 실제 운영 중인 컨텍스트 파일(AIOps 벤치마크의 프로젝트 `CLAUDE.md`: 클러스터 규칙, 점수 공식, 알려진 함정)입니다.

## 결과

### 비용: cache write 토큰

import나 심볼릭 링크가 로드되는 내용을 부풀렸다면 B의 cache write 토큰이 대조군 C보다 커야 합니다. 조건별 중앙값(셀당 n=12: 시나리오 4개 x 반복 3회):

| 모델 | A (native) | B (import) vs A | C (symlink, 대조군) vs A |
|---|---|---|---|
| Haiku 4.5 | 22,049 | -3% | +1% |
| Sonnet 4.6 | 14,357 | -3% | -1% |
| Sonnet 5 | 17,252 | +6% | +6% |
| Opus 4.8 | 15,542 | -4% | -1% |
| Fable 5 | 16,357 | -3% | -1% |

어느 행에서도 B가 대조군을 체계적으로 웃돌지 않습니다. 4개 모델에서는 import가 native보다 3~4% 낮았고, Sonnet 5에서는 6% 높았지만 같은 회차 묶음에서 심볼릭 링크 대조군도 똑같이 +6%였습니다. 심볼릭 링크는 메커니즘상 native와 달라질 수 없으므로, Sonnet 5의 편차는 전달 비용이 아니라 실행 편차입니다(그 조건들에서 output 토큰도 20% 안팎 같이 늘었습니다).

이 지표의 한계도 데이터에서 확인됐습니다. cache write 합계는 턴마다 쌓이는 값이라 풀이가 길어지면 커지고, 인접 회차와 조립 컨텍스트가 동일하면 서버측 프롬프트 캐시에 적중해 기록량이 급감할 수 있습니다(1회 관측). 회차마다 클러스터 스냅샷을 복원해도 API 레벨 캐시까지 차단되지는 않습니다.

### 속도: wall time

조건별 중앙값(초):

| 모델 | A | B | C |
|---|---|---|---|
| Haiku 4.5 | 22.1 | 22.8 | 29.8 |
| Sonnet 4.6 | 40.1 | 51.9 | 37.6 |
| Sonnet 5 | 49.7 | 53.7 | 47.8 |
| Opus 4.8 | 76.2 | 69.1 | 89.3 |
| Fable 5 | 79.2 | 90.6 | 76.5 |

편차가 커 보이지만 일관성이 없습니다. 부호가 모델과 조건마다 뒤집히고, 시간 편차가 가장 큰 곳의 토큰 편차는 거의 0입니다(예: Haiku C는 시간 +35%인데 토큰 +3%). 전달 방식의 오버헤드라면 부호가 한쪽으로 쏠려야 합니다. 이 패턴은 에이전트 풀이 경로의 편차입니다.

output 토큰과 tool call 수도 각각 ±15%, ±8% 안에서 부호가 섞여 사실상 차이가 없습니다.

## 방법

- **작업**: AIOps Agent Benchmark의 쿠버네티스 장애 대응 시나리오(깨진 배포, 잘못된 Service selector, OOM 한도, readiness probe 실패). 매 회차 클러스터 스냅샷 복원, 고장 주입, `--dangerously-skip-permissions`로 에이전트 실행, 콜드 스타트.
- **격리**: 에이전트는 해당 조건의 컨텍스트 파일만 든 새 임시 작업 디렉토리에서 돌고, 클러스터는 다른 벤치마크와 공유하지 않는 전용 2노드입니다. 모든 kubectl 명령은 `--context agents-md-migration`을 명시합니다.
- **공정성**: 시나리오마다 조건 순서를 섞어 시간대 드리프트가 한 조건에 몰리지 않게 했습니다. 사용자 레벨 `~/.claude/CLAUDE.md`는 세 조건에 똑같이 읽히므로 상쇄됩니다.
- **로드 검증 먼저**: 속도를 재기 전에, 본문에 카나리 한 줄("PING에 PONG-AGENTSMD로 답하라")을 넣어 각 조건이 실제로 읽히는지 확인했습니다. 세 조건 모두 응답했고 빈 디렉토리 대조군은 응답하지 않았습니다.
- **물량**: 10개 시나리오 x A/B/C 1차(30회, Sonnet 5), 이어서 편차가 작은 4개 시나리오 x A/B/C x 5모델 x 3반복 스윕(180회). 발행 대상 210회 전부 정상 종료(rc=0). 1회가 일시적 API 500 서버 오류로 실패해 인프라 실패 정책에 따라 재실행했습니다.

## 환경

| 항목 | 값 |
|---|---|
| Claude Code | 2.1.198(4모델 스윕), 2.1.199(Sonnet 5), 로드 검증은 2.1.195 |
| 모델 | claude-haiku-4-5, claude-sonnet-4-6, claude-sonnet-5, claude-opus-4-8, claude-fable-5 |
| Kubernetes | v1.36.2 (kubeadm), containerd 2.2.3, Ubuntu 24.04 |
| 클러스터 | 컨트롤플레인 1 + 워커 1, Vagrant + VirtualBox, Calico CNI, MetalLB |
| 측정 시점 | 2026-07-02 ~ 2026-07-04 |

| 노드 | 역할 | IP |
|---|---|---|
| cp-k8s | control-plane | 192.168.2.10 |
| w1-k8s | worker | 192.168.2.11 |

## 재현

```bash
# 1) 클러스터
cd test-cluster && ./up.sh && ./snapshot.sh    # baseline 스냅샷

# 2) 한 회차: 조건 x 시나리오 x 반복 태그
cd ../studies/agents-md-import-speed
./run_one.sh B 001-crashloop r1

# 3) 전체 1차와 모델 스윕
./run_suite.sh r1
REPS=3 bash run_model_sweep.sh

# 4) 집계
python3 report_sweep.py   # 모델 x 조건 중앙값
python3 aggregate.py      # 회차별 CSV
```

회차별 raw 데이터(`runs/`)와 측정에 쓴 payload(내부 운영 메모가 담긴 실제 프로젝트 `CLAUDE.md`)는 비공개 작업장에 남습니다. 이 저장소는 하네스 스크립트와 집계 결과를 공개합니다. 전달 방식만 다르므로, 바이트 동일한 아무 payload나 세 가지 `variants/` 배치로 두면 같은 비교가 재현됩니다. 집계 스크립트(`aggregate.py`, `report_sweep.py`)는 AIOps 벤치마크의 파서(비공개)를 import하므로 방법 문서로 보면 됩니다.

## 한계

- 정확성과 안전 채점(Ops_Score, audit 기반 결정론 unsafe 카운트)은 이번 측정에 포함하지 않았습니다. 이 연구는 속도와 토큰 비용 질문에 답합니다. audit 슬라이스는 회차마다 캡처해 두어 나중에 채점을 붙일 수 있습니다.
- 모델 스윕은 편차가 작은 4개 시나리오만 다뤘습니다. 어려운 시나리오(여러 단계 root cause 추적)는 조건당 1회뿐이라 풀이 경로 편차가 지배하며, 그래서 스윕 범위를 저편차 구간으로 잡았습니다.

## 선행 연구

- [arXiv 2601.20404](https://arxiv.org/abs/2601.20404)는 사람이 쓴 AGENTS.md를 Codex(AGENTS.md를 네이티브로 읽는 에이전트)에서 측정해 런타임 중앙값 -28.6%, 출력 토큰 -16.6%를 보고했습니다. 다만 import 우회나 네이티브가 아닌 리더는 측정하지 않았고, 그 부분을 이 연구가 Claude Code를 대상으로 측정했습니다.
- [ETH Zurich 연구(arXiv 2602.11988)](https://arxiv.org/abs/2602.11988)는 LLM이 생성한 AGENTS.md가 오히려 성공률을 낮추고 비용을 올린다고 보고했습니다. 파일을 어떻게 만들었는지가 결과를 좌우한다는 의미라, 이 연구는 파일을 사람이 다듬은 것으로 고정하고 전달 방식만 바꿨습니다.
