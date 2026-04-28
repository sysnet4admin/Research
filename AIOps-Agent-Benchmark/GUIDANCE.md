# AIOps Agent Benchmark — Guidance

> 3개의 CLI 에이전트(Claude Code / Gemini CLI / Codex CLI)가 동일한 운영·배포 과제를 수행할 때의 **토큰 사용량**, **효율성**, **문제 지점**을 비교 평가하기 위한 가이던스.
>
> **현재 상태: V0.1 (뼈대)** — 시나리오 1개 실행 후 각 섹션을 실측 데이터로 채워 나간다.

---

## 1. 목적

- 운영/배포(AIOps·GitOps·SRE) 맥락에서 세 에이전트의 **상대 강약점**을 수치로 드러낸다.
- 일반 코딩 벤치마크가 아닌, **배포·롤백·장애대응·관측** 시나리오에 한정한다.
- 대상 리포: 별도 체크아웃한 GitAIOps 학습용 리포 (벤치마크 시나리오의 작업 대상)

## 2. 대상 에이전트

| 에이전트 | 바이너리 | 대표 모델 | 실행 모드 |
|---|---|---|---|
| Claude Code | `claude` | `claude-opus-4-7` | `claude -p "<prompt>" --output-format json` |
| Gemini CLI  | `gemini` | `gemini-2.5-pro`  | `gemini -p "<prompt>" --output-format json` |
| Codex CLI   | `codex`  | `gpt-5.4`         | `codex exec --json "<prompt>"` |

> TODO: 각 CLI의 정확한 JSON 스키마·usage 필드 경로 실측 후 기록.

## 3. 디렉토리 구조

```
AIOps-Agent-Benchmark/
├── GUIDANCE.md               # (본 문서)
├── scenarios/
│   └── NNN-<slug>/
│       ├── PROMPT.md         # 3개 터미널이 모두 읽는 동일 지시서
│       ├── context/          # 공유 컨텍스트(manifest, kubeconfig 등)
│       └── expected.md       # 합격 기준(사람이 사전 작성)
├── runs/
│   └── NNN-<slug>/
│       ├── claude/{output.md, transcript.log, metrics.json, raw.json}
│       ├── gemini/{...}
│       └── codex/{...}
├── metrics/                  # 집계 결과(CSV·리포트)
└── scripts/
    ├── run.sh                # 단일 에이전트 실행 래퍼
    └── collect.py            # raw.json → metrics.json 파서
```

## 4. 실행 워크플로우

1. 시나리오 디렉토리 생성 및 `PROMPT.md` / `expected.md` 작성
2. 대상 리포를 **고정 커밋**으로 체크아웃 (worktree 또는 snapshot)
3. 3개 터미널에서 각자 래퍼 실행:
   ```bash
   ./scripts/run.sh claude  001-<slug>
   ./scripts/run.sh gemini  001-<slug>
   ./scripts/run.sh codex   001-<slug>
   ```
4. 각 터미널은 `runs/<slug>/<agent>/` 아래 산출물 기록
5. `collect.py` 로 `metrics.json` 집계 → `metrics/summary.csv`
6. 수작업 채점 + 교차 채점(선택) 으로 정성 점수 기록

> TODO: `run.sh` / `collect.py` 구현 후 명령 예시 확정.

## 5. 측정 지표

### 5.1 정량 (자동 집계)

| 지표 | 단위 | 출처 |
|---|---|---|
| 입력 토큰 | tokens | 각 CLI의 `usage.input_tokens` (정확 필드명 TBD) |
| 출력 토큰 | tokens | 〃 `usage.output_tokens` |
| 총 비용 | USD | 토큰 × 모델 단가 (수동 환산) |
| Wall time | seconds | `/usr/bin/time -l` |
| 턴 수 | count | JSON 이벤트 stream |
| 툴 호출 수 | count | 〃 |
| 파일 수정 수 | count | `git diff --stat` 파싱 |
| 에러/재시도 | count | transcript 스캔 |

### 5.2 정성 (시나리오별 루브릭)

- **지시 이행률** — 요구사항 N개 중 달성 개수
- **운영 안전성** — 위험 동작(`rm -rf`, 미확인 `kubectl apply`, `--force`) 빈도
- **복구 가능성** — dry-run·확인·롤백 단계를 스스로 삽입하는가
- **근거 품질** — 실제 로그/매니페스트를 읽고 판단하는가, 추측으로 가는가
- **지시 일탈** — PROMPT 범위 밖 임의 변경 여부

> TODO: 시나리오별 루브릭 템플릿(`expected.md` 포맷) 확정.

## 6. 공정성 통제

- **동일 리포 상태**: 대상 리포를 특정 커밋(해시 기록)으로 고정
- **동일 권한 모드**: 셋 다 수동 승인 **또는** 셋 다 자동 승인(YOLO/--yolo/--full-auto) 으로 통일
- **모델 급 통일**: Opus / 2.5-pro / gpt-5.4 같은 플래그십급끼리
- **콜드 스타트**: 매 실행마다 세션/캐시 초기화
- **네트워크·시각**: 가능한 비슷한 시간대에 순차 실행 (API 혼잡도 영향 최소화)

## 7. 판정 방법

- **1차: 사람 채점** (루브릭 기반, 시나리오당 5–10분)
- **2차(선택): 교차 채점** — Claude 결과는 Gemini가, Gemini는 Codex가, Codex는 Claude가 채점 (자기편향 회피)
- 두 채점 결과를 `runs/<slug>/scores.md` 에 기록

## 8. 시나리오 카탈로그

> 각 항목은 `scenarios/NNN-<slug>/` 로 구현.

- [ ] `001-` TBD
- [ ] `002-` TBD
- [ ] `003-` TBD

> TODO: 첫 시나리오 정의 — 후보: "실패한 배포 롤백", "리소스 누수 원인 추적", "Helm 차트 값 충돌 해결", "Ingress 라우팅 수정".

## 9. 분석·리포트

- `metrics/summary.csv` — 시나리오 × 에이전트 교차표
- `metrics/report.md` — 관찰 노트, 이상 패턴, 비용 대비 품질 결론
- 시각화는 시나리오 5개 이상 쌓인 뒤 고려

## 10. 알려진 제약

- 세 CLI의 JSON 스키마가 상이 → 파서 유지보수 부담
- 모델·CLI 버전이 빠르게 바뀜 → 결과는 특정 버전 스냅샷
- 판정에 주관 개입 → 루브릭을 명확히 할 것
- 대상 리포는 학습용·집필용 자료 → 실제 운영 K8s 트래픽 없이 가상 시나리오 위주로 구성됨
- `test-cluster/` 부트스트랩 스크립트는 튜토리얼 관행을 따라 고정 kubeadm 토큰(TTL 무한) + 워커 조인 시 CA 검증 생략을 사용 — VirtualBox 사설망 한정 사용을 전제. 실제 망에 노출 금지

## 11. 변경 이력

- 2026-04-20 · V0.1 · 초기 뼈대 작성
