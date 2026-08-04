#!/usr/bin/env bash
# 본 캠페인 종료를 감시하다가, 마감까지 시간이 남으면 추가 회차를 자동 실행한다.
# (실행 중인 run_campaign.sh는 수정 불가라 별도 감시자로 구현)
# 사용: nohup ./follow_on.sh <메인 progress.log 경로> <최종 마감 epoch> &
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(dirname "$DIR")"
CLUSTER="$STUDY/../../test-cluster"
MAIN_LOG="${1:?메인 progress.log 필요}"
FINAL_DEADLINE="${2:?최종 마감 epoch 필요}"
CTX="cni-benchmark"
LOG="$STUDY/runs/follow_on.log"
log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "감시 시작: $MAIN_LOG 의 '캠페인 종료' 대기"

# 본 캠페인 종료 대기 (10분 간격 폴링)
while ! grep -q "캠페인 종료" "$MAIN_LOG" 2>/dev/null; do
  sleep 600
done
log "본 캠페인 종료 감지"

# 남은 시간 확인: 추가 조건 1개(약 4시간) + 여유가 안 되면 그냥 끝
LEFT=$(( FINAL_DEADLINE - $(date +%s) ))
if [ "$LEFT" -lt 18000 ]; then
  log "남은 시간 $((LEFT/3600))h < 5h, 추가 회차 없이 종료"
  exit 0
fi
log "남은 시간 $((LEFT/3600))h, 추가 회차 시작"

# 클러스터 재기동 (본 캠페인이 halt로 끝냄)
( cd "$CLUSTER" && vagrant up ) >>"$LOG" 2>&1
start=$SECONDS
until kubectl --context "$CTX" get nodes >/dev/null 2>&1; do
  [ $((SECONDS - start)) -gt 600 ] && { log "ERROR: 클러스터 재기동 실패"; exit 1; }
  sleep 15
done
log "클러스터 재기동 완료"

# 추가 회차: 짧은 idle, 시간 되는 만큼 (마감 인지는 러너가 함)
OUT="$STUDY/runs/extra-$(date +%m%d-%H%M)"
mkdir -p "$OUT"
MAX_REP=2 IDLE_LONG=3600 IDLE_SHORT=3600 \
  caffeinate -i "$DIR/run_campaign.sh" "$OUT" "$FINAL_DEADLINE" >>"$LOG" 2>&1
log "추가 회차 종료"
