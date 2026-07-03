#!/usr/bin/env bash
# sonnet5_rerun.sh: Sonnet 티어를 claude-sonnet-5로 재측정 (발행 데이터 전체 갱신용, 2026-07-03).
#
# 배경: 최초 측정은 claude-sonnet-4-6(AIOps Efficient 티어 연속성). 발행 시점 기준
# 최신 기본 모델이 Sonnet 5라 사용자 결정으로 재측정. 기존 sonnet-4-6 데이터는
# runs/에 그대로 보존(비교 근거).
#
# 구성 (66회):
#   1) sonnet-5 스윕: 4 시나리오 x A/B/C x 3반복 = 36회 (표의 Sonnet 행 대체)
#   2) r2 전체 통과: 10 시나리오 x A/B/C = 30회 (1단계 데이터 대체)
# 스윕을 먼저 돌린다(표 수치가 더 급함). 이미 있는 회차는 건너뜀(재개 안전).
#
# 실행: nohup caffeinate -i bash sonnet5_rerun.sh > /tmp/agentsmd-sonnet5.log 2>&1 &

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CLAUDE_MODEL=claude-sonnet-5

echo "=== sonnet5 rerun start $(date '+%F %T') (model=$CLAUDE_MODEL) ==="

echo "--- phase 1: sweep (4 scen x 3 cond x 3 rep) ---"
for rep in 1 2 3; do
  for S in 001-crashloop 002-service 003-oom 004-readiness; do
    CONDS=$(printf 'A\nB\nC\n' | sort -R | tr '\n' ' ')
    echo "--- $S / sonnet5 / rep$rep : order = $CONDS ---"
    for C in $CONDS; do
      if [ -f "$HERE/runs/agentsmd-${C}-${S}-sonnet5-r${rep}/meta.json" ]; then
        echo "  skip existing agentsmd-${C}-${S}-sonnet5-r${rep}"
        continue
      fi
      bash "$HERE/run_one.sh" "$C" "$S" "sonnet5-r${rep}" \
        || echo "!!! $S/$C/sonnet5-r$rep failed, continuing" >&2
    done
  done
done

echo "--- phase 2: full pass r2 (10 scen x 3 cond) ---"
bash "$HERE/run_suite.sh" r2

echo "=== sonnet5 rerun all done $(date '+%F %T') ==="
