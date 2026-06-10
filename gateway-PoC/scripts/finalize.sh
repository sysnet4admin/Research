#!/usr/bin/env bash
# scoring 파이프라인 일괄 실행 (정식 5단계).
#
# 공개 results/aggregated.json은 단순 집계가 아니라 두 캠페인의 병합 산출이다:
#   - 결정론 항목: v3 캠페인(results/rounds-v3, 35테스트, 신규 graded Extended 포함)
#   - canary(가중 라우팅): 기존 155라운드 풀(results/rounds) 보존(발표 메트릭 동결)
# 단순히 `aggregate.py`를 기본값(--rounds results/rounds)으로 돌리면 v3 확장테스트가
# 빠진 19테스트로 aggregated.json을 덮어써 공개본을 손상시킨다(aggregated.json은
# gitignore라 복구 불가). 그래서 이 스크립트가 5단계 전부를 단일 실행 기록으로 담는다.
set -euo pipefail
cd "$(dirname "$0")"

RES=../results

# 1) v3 캠페인 집계(결정론 항목 35종)
python3 aggregate.py --rounds "$RES/rounds-v3" --out "$RES/aggregated-v3-fresh.json"
# 2) v2 155라운드 집계(canary 풀 소스)
python3 aggregate.py --rounds "$RES/rounds" --out "$RES/aggregated-v2-155round.json"
# 3) 병합: 결정론=v3, canary=155풀 → 공개 aggregated.json
python3 merge_canary.py --new "$RES/aggregated-v3-fresh.json" \
                        --old "$RES/aggregated-v2-155round.json" \
                        --out "$RES/aggregated.json"
# 3b) 운영 테스트(failover-recovery 등) 격리 캠페인(rounds-ops) 병합(있을 때만).
#     데이터플레인 강제 재시작이라 결정론/canary와 분리 측정 후 주입.
if ls "$RES"/rounds-ops/round-*.json >/dev/null 2>&1; then
  python3 aggregate.py --rounds "$RES/rounds-ops" --out "$RES/aggregated-ops.json"
  python3 merge_ops.py --agg "$RES/aggregated.json" --ops "$RES/aggregated-ops.json" \
                       --tests "failover-recovery retry health-check" --out "$RES/aggregated.json"
fi
# 3c) 공정성 재측정 병합(2026-06-10, 설정 교정). cross-vendor deep research에서 드러난
#     설정 의존 오답을 의도대로 측정해 정정. kong=expressions 라우터(query-param 등),
#     kgateway=TrafficPolicy basicAuth. 해당 impl의 그 test만 주입.
if ls "$RES"/rounds-kong-expr/round-*.json >/dev/null 2>&1; then
  python3 aggregate.py --rounds "$RES/rounds-kong-expr" --out "$RES/aggregated-kong-expr.json"
  python3 merge_ops.py --agg "$RES/aggregated.json" --ops "$RES/aggregated-kong-expr.json" \
                       --tests "query-param-matching method-matching grpc-routing" --out "$RES/aggregated.json"
fi
if ls "$RES"/rounds-kgw-ba/round-*.json >/dev/null 2>&1; then
  python3 aggregate.py --rounds "$RES/rounds-kgw-ba" --out "$RES/aggregated-kgw-ba.json"
  python3 merge_ops.py --agg "$RES/aggregated.json" --ops "$RES/aggregated-kgw-ba.json" \
                       --tests "basic-auth" --out "$RES/aggregated.json"
fi
# 4) 채점  5) 리포트
python3 score.py
python3 report.py

# 가드: 병합 산출물이 canary 풀 provenance를 담았는지 확인(단순 aggregate 클로버 방지)
python3 - "$RES/aggregated.json" <<'PY'
import json, sys
a = json.load(open(sys.argv[1]))
src = a.get("canary_source", {}).get("from")
assert src == "frozen-155-round-pool", \
    f"aggregated.json에 canary 풀 provenance 없음(src={src!r}). 5단계 흐름이 깨졌다."
print(f"guard OK: canary_source={src} | rounds(결정론)={a.get('rounds')}")
PY
echo "완료: results/aggregated.json, results/scores.json, metrics/{conformance,migration}-view/"
