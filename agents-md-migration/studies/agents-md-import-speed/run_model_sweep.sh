#!/usr/bin/env bash
# run_model_sweep.sh: 모델 축 스윕. 001~004 x A/B/C x {haiku,sonnet,opus,fable} x N reps.
#
# 목적: A/B/C 전달 방식 오버헤드가 모델 티어와 무관하게(저하 없음) 유지되는지 확인.
# A/B/C 차이는 Claude Code가 모델 호출 전에 해소하므로 원리상 모델 무관. 이 스윕은
# 그 "저하 없음"이 Haiku~Fable 전 티어에서 일반화되는지 실측으로 보인다.
#
# 회차 dir 이름 충돌 방지 위해 tag에 "<modelshort>-r<rep>"를 넣는다.
#   예: agentsmd-A-001-crashloop-opus-r2
#
# 장시간(약 5h)이라 nohup 분리로 실행:
#   nohup caffeinate -i bash run_model_sweep.sh > /tmp/agentsmd-sweep.log 2>&1 &

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPS="${REPS:-3}"
SCENARIOS=(001-crashloop 002-service 003-oom 004-readiness)

MODELS=(
  "haiku:claude-haiku-4-5"
  "sonnet:claude-sonnet-4-6"
  "opus:claude-opus-4-8"
  "fable:claude-fable-5"
)

echo "=== model sweep: ${#SCENARIOS[@]} scen x 3 cond x ${#MODELS[@]} models x N=$REPS, start $(date '+%F %T') ==="

for rep in $(seq 1 "$REPS"); do
  for SCENARIO in "${SCENARIOS[@]}"; do
    for entry in "${MODELS[@]}"; do
      SHORT="${entry%%:*}"; FULL="${entry##*:}"
      TAG="${SHORT}-r${rep}"
      CONDS=$(printf 'A\nB\nC\n' | sort -R | tr '\n' ' ')
      echo "--- $SCENARIO / $SHORT / rep$rep : order = $CONDS ---"
      for COND in $CONDS; do
        if [ -f "$HERE/runs/agentsmd-${COND}-${SCENARIO}-${TAG}/meta.json" ]; then
          echo "  skip existing agentsmd-${COND}-${SCENARIO}-${TAG}"
          continue
        fi
        CLAUDE_MODEL="$FULL" bash "$HERE/run_one.sh" "$COND" "$SCENARIO" "$TAG" \
          || echo "!!! $SCENARIO/$COND/$SHORT/rep$rep failed, continuing" >&2
      done
    done
  done
done

echo "=== model sweep all done $(date '+%F %T') ==="
