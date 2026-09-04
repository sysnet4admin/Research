#!/usr/bin/env bash
# rv 체인6 (2026-09-03): 체인5(18:00 reuse A/B)의 완료 체크포인트를 기다렸다가
# tail 보강(rv_tail.sh)을 잇는다. chain_rv5.sh 구조의 최소 델타.
# 사용: caffeinate -i nohup ./chain_rv6.sh > /tmp/rv-chain6.log 2>&1 &
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
REPO="$(cd "$STUDY/.." && pwd)"
PY="$HOME/.venvs/mcpbench/bin/python"
CKPT="$STUDY/runs/.rv6-ckpt"
PREV="$STUDY/runs/.rv5-ckpt-abr"
log() { echo "[chain6 $(date '+%m-%d %H:%M')] $*"; }
push() { ( cd "$REPO" && git add agentgateway-study/runs >/dev/null 2>&1 \
  && git commit -q -m "rv 체인6: $1" >/dev/null 2>&1 \
  && git pull --rebase --autostash -q origin main >/dev/null 2>&1 \
  && git push -q origin main >/dev/null 2>&1 ) || true; }
wait_ac() {
  local waited=0
  until pmset -g batt | grep -q 'AC Power'; do
    [ $waited -eq 0 ] && log "AC 이탈 감지. 복귀 대기"
    sleep 120; waited=$((waited+120))
    [ $waited -ge 43200 ] && { log "AC 12시간 미복귀. 중단"; exit 1; }
  done
  [ $waited -gt 0 ] && log "AC 복귀(${waited}s 대기)"
}
preflight_retry() { # 마감 없이 10분 간격 재시도 (최대 12시간)
  local tries=0
  while :; do
    colima stop >/dev/null 2>&1; pkill -f 'hugo server' 2>/dev/null
    if "$DIR/preflight_rv.sh"; then return 0; fi
    tries=$((tries+1)); [ $tries -ge 72 ] && { log "사전 점검 12시간 미통과. 중단"; return 1; }
    log "사전 점검 실패. 10분 후 재시도"
    sleep 600
  done
}
log "체인5 완료 대기 ($PREV)"
while [ ! -f "$PREV" ]; do
  pgrep -f chain_rv5.sh >/dev/null || { log "체인5 프로세스 없음 + 체크포인트 없음. 중단"; exit 1; }
  sleep 60
done
log "체인5 완료 확인"
sleep 120  # 체인5 푸시와 정리 여유
preflight_retry || exit 1
if [ -f "$CKPT-tail" ]; then log "=== 단계 건너뜀(완료 체크포인트): tail 보강 ==="; else
  wait_ac
  log "=== 단계 시작: tail 보강 ==="
  ( cd "$STUDY" && ./harness/rv_tail.sh "$PY" runs/rv-tail-0903 ); rc=$?
  if [ $rc -ne 0 ]; then log "=== 단계 실패($rc): tail 보강 ==="; push "단계 실패 tail 보강"; exit $rc; fi
  touch "$CKPT-tail"
  log "=== 단계 완료: tail 보강 ==="; push "단계 완료 tail 보강"
fi
log "=== 체인6 전체 종료 ==="
