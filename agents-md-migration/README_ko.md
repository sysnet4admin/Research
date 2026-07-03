# AGENTS.md 마이그레이션

[English](README.md)

프로젝트 컨텍스트 파일을 `CLAUDE.md`에서 **AGENTS.md**로 옮기면 Claude Code가 느려지거나 비용이 늘어날까? [AGENTS.md](https://agents.md/)는 AAIF(Agentic AI Foundation, Linux Foundation)가 관리하는 열린 컨텍스트 파일 형식으로, 30개가 넘는 코딩 에이전트가 읽는다. 그런데 Claude Code는 이 파일을 그대로는 읽지 않아서([issue #34235](https://github.com/anthropics/claude-code/issues/34235)), 마이그레이션하려면 둘 중 하나가 필요하다. `CLAUDE.md` 안에 `@AGENTS.md` import 한 줄을 두거나, `CLAUDE.md`를 `AGENTS.md`로 가는 심링크로 바꾸는 것이다. 이 연구는 그 두 우회로에 실제 비용이 있는지를 쿠버네티스 장애 대응 작업 위에서 측정했다.

> 시나리오, 채점 파서, audit 캡처는 같이 공개된 [AIOps Agent Benchmark](https://github.com/sysnet4admin/Research/tree/main/AIOps-Agent-Benchmark)를 재사용한다. 이 연구는 Claude Code 하나만 측정하며, 벤더 간 비교가 아니다.

## 요약

- **세 가지 전달 방식 모두 실제로 읽힌다.** 카나리 검증으로 `@AGENTS.md` import와 심링크 둘 다 Claude Code가 따라가는 것을 확인했다(컨텍스트 없는 대조군만 카나리에 응답하지 않았다).
- **속도 저하가 없다.** 4개 모델 티어(Haiku 4.5, Sonnet 4.6, Opus 4.8, Fable 5) 전부에서 wall time 편차의 부호가 조건마다 뒤바뀌고 토큰 편차와도 어긋난다. 이는 컨텍스트 로드 오버헤드가 아니라 LLM 실행 편차의 특징이다.
- **토큰 비용 페널티가 없다.** 세션 시작 때 한 번 발생하는 컨텍스트 로드 토큰(cache write)이 어느 우회로에서도 늘지 않는다. import 형태는 오히려 네 모델 모두에서 native보다 약 3% 낮게 측정됐고, 심링크는 native와 ±1% 안이다.

## 조건

세 조건의 본문(payload)은 체크섬으로 검증한 바이트 동일 문서다. 전달 방식만 다르다.

| 조건 | 에이전트 작업 디렉토리의 파일 | Claude Code가 읽는 경로 |
|---|---|---|
| **A** native | `CLAUDE.md`(본문) | `CLAUDE.md`를 바로 읽음 |
| **B** import | `CLAUDE.md`(`@AGENTS.md` 한 줄) + `AGENTS.md`(본문) | `@AGENTS.md` import를 따라감 |
| **C** symlink | `AGENTS.md`(본문) + 그리로 가는 `CLAUDE.md` 심링크 | 심링크를 따라감 |

본문은 합성 문서가 아니라 실제 운영 중인 컨텍스트 파일(AIOps 벤치마크의 프로젝트 `CLAUDE.md`: 클러스터 규칙, 점수 공식, 알려진 함정)이다.

## 결과

### 비용: 일회성 컨텍스트 로드 토큰 (cache write)

import나 심링크가 로드되는 내용을 부풀렸다면 B나 C의 cache write 토큰이 A보다 커야 한다. 조건별 중앙값(셀당 n=12: 시나리오 4개 x 반복 3회):

| 모델 | A (native) | B (import) vs A | C (symlink) vs A |
|---|---|---|---|
| Haiku 4.5 | 22,049 | -3% | +1% |
| Sonnet 4.6 | 14,357 | -3% | -1% |
| Opus 4.8 | 15,542 | -4% | -1% |
| Fable 5 | 16,357 | -3% | -1% |

import는 네 티어 모두에서 오히려 조금 낮다. 캐시에 안 탄 순수 입력 토큰도 조건 간 0에서 -4%로 평평하다.

### 속도: wall time

조건별 중앙값(초):

| 모델 | A | B | C |
|---|---|---|---|
| Haiku 4.5 | 22.1 | 22.8 | 29.8 |
| Sonnet 4.6 | 40.1 | 51.9 | 37.6 |
| Opus 4.8 | 76.2 | 69.1 | 89.3 |
| Fable 5 | 79.2 | 90.6 | 76.5 |

편차가 커 보이지만 체계가 없다. 부호가 모델과 조건마다 뒤집히고, 시간 편차가 가장 큰 곳의 토큰 편차는 거의 0이다(예: Haiku C는 시간 +35%인데 토큰 +3%). 전달 방식의 오버헤드라면 부호가 한쪽으로 쏠려야 한다. 이 패턴은 에이전트 풀이 경로의 편차다.

output 토큰과 tool call 수도 각각 ±15%, ±8% 안에서 부호가 섞여 평평하다.

## 방법

- **작업**: AIOps Agent Benchmark의 쿠버네티스 장애 대응 시나리오(깨진 배포, 잘못된 Service selector, OOM 한도, readiness probe 실패). 매 회차 클러스터 스냅샷 복원, 고장 주입, `--dangerously-skip-permissions`로 에이전트 실행, 콜드 스타트.
- **격리**: 에이전트는 해당 조건의 컨텍스트 파일만 든 새 임시 작업 디렉토리에서 돌고, 클러스터는 다른 벤치마크와 공유하지 않는 전용 2노드다. 모든 kubectl 명령은 `--context agents-md-migration`을 명시한다.
- **공정성**: 시나리오마다 조건 순서를 섞어 시간대 드리프트가 한 조건에 몰리지 않게 했다. 사용자 레벨 `~/.claude/CLAUDE.md`는 세 조건에 똑같이 읽히므로 상쇄된다.
- **로드 검증 먼저**: 속도를 재기 전에, 본문에 카나리 한 줄("PING에 PONG-AGENTSMD로 답하라")을 넣어 각 조건이 실제로 읽히는지 확인했다. 세 조건 모두 응답했고 빈 디렉토리 대조군은 응답하지 않았다.
- **물량**: 10개 시나리오 x A/B/C 1차(30회, Sonnet), 이어서 편차가 작은 4개 시나리오 x A/B/C x 4모델 x 3반복 스윕(144회). 174회 전부 정상 종료(rc=0).

## 환경

| 항목 | 값 |
|---|---|
| Claude Code | 2.1.198 (로드 검증은 2.1.195) |
| 모델 | claude-haiku-4-5, claude-sonnet-4-6, claude-opus-4-8, claude-fable-5 |
| Kubernetes | v1.36.2 (kubeadm), containerd 2.2.3, Ubuntu 24.04 |
| 클러스터 | 컨트롤플레인 1 + 워커 1, Vagrant + VirtualBox, Calico CNI, MetalLB |
| 측정 시점 | 2026-07-02 |

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

회차별 raw 데이터(`runs/`)와 측정에 쓴 payload(내부 운영 메모가 담긴 실제 프로젝트 `CLAUDE.md`)는 비공개 작업장에 남는다. 이 저장소는 하네스 스크립트와 집계 결과를 공개한다. 전달 방식만 다르므로, 바이트 동일한 아무 payload나 세 가지 `variants/` 배치로 두면 같은 비교가 재현된다. 집계 스크립트(`aggregate.py`, `report_sweep.py`)는 AIOps 벤치마크의 파서(비공개)를 import하므로 방법 문서로 보면 된다.

## 한계

- 정확성과 안전 채점(Ops_Score, audit 기반 결정론 unsafe 카운트)은 이번 측정에 포함하지 않았다. 이 연구는 속도와 토큰 비용 질문에 답한다. audit 슬라이스는 회차마다 캡처해 두어 나중에 채점을 붙일 수 있다.
- 모델 스윕은 편차가 작은 4개 시나리오만 다뤘다. 어려운 시나리오(여러 단계 root cause 추적)는 조건당 1회뿐이라 풀이 경로 편차가 지배하며, 그래서 스윕 범위를 저편차 구간으로 잡았다.

## 선행 연구

- [arXiv 2601.20404](https://arxiv.org/abs/2601.20404)는 사람이 쓴 AGENTS.md를 Codex(AGENTS.md를 네이티브로 읽는 에이전트)에서 측정해 런타임 중앙값 -28.6%, 출력 토큰 -16.6%를 보고했다. 다만 import 우회나 네이티브가 아닌 리더는 측정하지 않았고, 이 연구가 Claude Code에 대해 그 공백을 채운다.
- ETH Zurich 연구는 LLM이 생성한 AGENTS.md가 오히려 성공률을 낮추고 비용을 올린다고 보고했다. 파일 품질이 방향을 가른다는 뜻이라, 이 연구는 파일을 사람이 다듬은 것으로 고정하고 전달 방식만 바꿨다.
