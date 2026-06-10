# scoring 파이프라인

측정/채점/집계/리포트 분리(SCORING.md 6장). 클러스터 무관, 순수 데이터 변환이라
오프라인 실행/검증 가능. rubric.yaml(동결 채점 계약)을 소비한다.

## 정식 흐름 (5단계)

공개 `results/aggregated.json`은 두 캠페인의 병합 산출이다:
- 결정론 항목: v3 캠페인(`results/rounds-v3`, 35테스트, 신규 graded Extended 포함)
- canary(가중 라우팅): 기존 155라운드 풀(`results/rounds`) 보존(발표 메트릭 동결)

```
results/rounds-v3/round-N.json ─ aggregate.py ─▶ results/aggregated-v3-fresh.json   (결정론 35테스트)
results/rounds/round-N.json    ─ aggregate.py ─▶ results/aggregated-v2-155round.json (canary 155풀)
                          └ merge_canary.py(결정론=v3, canary=155풀) ─▶ results/aggregated.json
                                                  │  score.py  ─▶ results/scores.json
                                                  ▼  report.py ─▶ metrics/{conformance,migration}-view/
```

round-N.json 스키마는 `gwlib.py` 상단 주석 참조.

## 실행

```bash
./finalize.sh          # 위 5단계 전부 + canary 풀 가드
```

주의: `aggregate.py`만 단독으로 기본값(`--rounds results/rounds`)으로 돌리지 말 것.
v3 확장테스트가 빠진 19테스트로 `aggregated.json`을 덮어써 공개본을 손상시킨다
(`aggregated.json`은 gitignore라 git 복구 불가). 반드시 `finalize.sh`를 쓴다.

## 오프라인 검증 (합성 데이터)

```bash
python3 _gen_synthetic.py                                   # results/_synthetic/round-1..3.json (격리)
python3 aggregate.py --rounds results/_synthetic --out /tmp/synth_agg.json
python3 score.py --agg /tmp/synth_agg.json --out /tmp/synth_scores.json
```

합성 라운드는 실제 `results/rounds`와 **분리된** `results/_synthetic`에 쓰이고 각
라운드에 `synthetic:true` 마커가 박힌다. `gwlib.load_rounds`가 이 마커를 보면 경고를
출력하므로, 실수로 실제 집계에 섞여도 드러난다. `_gen_synthetic.py`는 round-N.json
스키마의 실행 가능한 참조이기도 하다.

## 채점 규칙(동결, SCORING.md)

- supported = pass_rate == 1.0 (전 라운드 통과). 실제 통과율/분산은 리포트에 표기.
  canary는 표본 테스트라 누적 풀링 split이 목표(80/20)에 2σ 내로 수렴하면 supported.
- Core 적합성 = 7개 Core 전부 supported. 하나라도 실패면 Non-conformant.
- Extended 폭 = 지원 Extended-standard 수 / 13 (v3 확장 후 5→13).
- 실험(retry, session-affinity 등)과 비표준 매트릭스 항목은 등급 미반영, 매트릭스로 보고.
- infra-excluded 라운드는 분모 제외, not-configured는 데이터 오류로 플래그.
