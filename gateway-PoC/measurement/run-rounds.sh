#!/usr/bin/env bash
# 자율 다중 라운드 러너. 목표 시각까지 라운드를 반복하고(중간 실패해도 계속),
# 라운드마다 누적 채점한다. AIOps bench_run_until 참고.
#
# 함정 회피(AIOps 교훈): 시간 기반 종료가 마지막 라운드를 자르지 않도록,
# 남은 시간이 한 라운드 예산보다 적으면 새 라운드를 시작하지 않는다.
# 이어달리기: 기존 round-*.json 다음 번호부터 시작.
#
# 사용: TARGET="2026-06-04 06:00" MAX_ROUNDS=30 ./run-rounds.sh
#   (caffeinate로 감싸 백그라운드 실행 권장)

set -uo pipefail   # -e 미사용: 라운드 실패가 루프를 멈추지 않게
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
export KUBE_CONTEXT="${KUBE_CONTEXT:-gateway-PoC}"

TARGET="${TARGET:-2026-06-04 06:00}"        # 이 시각 전까지만 새 라운드 시작
MAX_ROUNDS="${MAX_ROUNDS:-30}"              # 안전 상한
ROUND_BUDGET="${ROUND_BUDGET:-2700}"        # 한 라운드 예산(초) ~45분. 남은시간 < 이값이면 중단

# 목표 시각 epoch (macOS date -j / GNU date 둘 다 시도)
target_epoch="$(date -j -f "%Y-%m-%d %H:%M" "$TARGET" +%s 2>/dev/null || date -d "$TARGET" +%s 2>/dev/null)"
RESULTS="$(cd "$HERE/.." && pwd)/results/rounds"
SCRIPTS="$(cd "$HERE/.." && pwd)/scripts"
mkdir -p "$RESULTS"

count_rounds() { ls "$RESULTS"/round-*.json 2>/dev/null | wc -l | tr -d ' '; }
start=$(( $(count_rounds) + 1 ))

echo "########## 자율 다중 라운드 시작 $(date) ##########"
echo "목표 종료: $TARGET (epoch=$target_epoch), 시작 라운드: $start, 상한: $MAX_ROUNDS"

r=$start
while [ "$r" -le "$MAX_ROUNDS" ]; do
  now="$(date +%s)"
  remain=$(( target_epoch - now ))
  if [ "$remain" -lt "$ROUND_BUDGET" ]; then
    echo "남은 시간 ${remain}s < 예산 ${ROUND_BUDGET}s → 새 라운드 시작 중단(마지막 라운드 보호)"
    break
  fi
  echo ""
  echo "============ ROUND $r 시작 $(date) (남은 ${remain}s) ============"
  if ROUND="$r" ./run-round.sh > "round_${r}.log" 2>&1; then
    echo "ROUND $r 측정 완료 $(date)"
  else
    echo "ROUND $r 측정 실패(rc=$?), 로그 round_${r}.log — 계속 진행"
  fi
  # 라운드마다 누적 채점(부분 결과 항상 가용)
  if ( cd "$SCRIPTS" && ./finalize.sh ) >/dev/null 2>&1; then
    echo "ROUND $r 누적 채점 갱신(총 $(count_rounds)라운드)"
  else
    echo "ROUND $r 채점 실패 — 계속"
  fi
  r=$(( r + 1 ))
done

echo ""
echo "########## 종료 $(date). 총 $(count_rounds)라운드 ##########"
( cd "$SCRIPTS" && ./finalize.sh ) >/dev/null 2>&1 || true
echo "최종 리포트: gateway-PoC/metrics/report.html, README_tables.md"
