#!/usr/bin/env bash
# run_suite.sh: 시나리오 세트 x A/B/C 스위트 실행.
#
# 각 시나리오마다 조건 순서를 섞어(shuffle) 시간대 드리프트가 특정 조건에 몰리지 않게
# 한다(design.md 3장). 개별 회차는 run_one.sh가 담당(리셋 - 시딩 - 실행 - 캡처).
#
# Usage: ./run_suite.sh <rep-tag> [scenario ...]
#   예:  ./run_suite.sh r1                       # 10개 시나리오 전부
#        ./run_suite.sh r1 001-crashloop 002-service
#
# 장시간 실행이므로 호출은 caffeinate로 감싼다:
#   caffeinate -i nohup ./run_suite.sh r1 > /tmp/agentsmd-suite-r1.log 2>&1 &

set -uo pipefail

TAG="${1:?Usage: $0 <rep-tag> [scenario ...]}"
shift || true

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -gt 0 ]; then
  SCENARIOS=("$@")
else
  SCENARIOS=(001-crashloop 002-service 003-oom 004-readiness 005-pvc
             006-hpa 007-evict 008-throttle 009-ext-dep 010-chaos)
fi

echo "=== suite $TAG: ${#SCENARIOS[@]} scenarios x 3 conds, start $(date '+%F %T') ==="

for SCENARIO in "${SCENARIOS[@]}"; do
  # 조건 순서 셔플 (시나리오마다 다르게)
  CONDS=$(printf 'A\nB\nC\n' | sort -R | tr '\n' ' ')
  echo "--- $SCENARIO: order = $CONDS ---"
  for COND in $CONDS; do
    bash "$HERE/run_one.sh" "$COND" "$SCENARIO" "$TAG"
    RC=$?
    if [ "$RC" -ne 0 ]; then
      echo "!!! $SCENARIO/$COND failed (rc=$RC). continuing with next." >&2
    fi
  done
done

echo "=== suite $TAG done $(date '+%F %T') ==="
