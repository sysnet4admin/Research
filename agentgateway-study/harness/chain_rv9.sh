#!/usr/bin/env bash
# rv 체인9 (2026-09-05 토): 체인8 완료 체크포인트 대기 -> 게이트 -> 혼합 30분 close 창 귀속(rv_mixed_sus.sh, direct 대 gw).
# chain_rv4.sh의 최소 델타 사본(단계 1개). 상주 환경(v1.5.0 게이트웨이, mcp-b) 재사용.
# 사용: caffeinate -i nohup ./chain_rv9.sh > /tmp/rv-chain9.log 2>&1 &
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
REPO="$(cd "$STUDY/.." && pwd)"
CTX="aaif-benchmark"
PY="$HOME/.venvs/mcpbench/bin/python"
CKPT="$STUDY/runs/.rv9-ckpt"
log() { echo "[chain9 $(date '+%m-%d %H:%M')] $*"; }
push() { ( cd "$REPO" && git add agentgateway-study/runs >/dev/null 2>&1 \
  && git commit -q -m "rv 체인9: $1" >/dev/null 2>&1 \
  && git pull --rebase --autostash -q origin main >/dev/null 2>&1 \
  && git push -q origin main >/dev/null 2>&1 ) || true; }
wait_until() { while [ "$(date '+%H%M')" -lt "$1" ]; do sleep 60; done; }
wait_ac() {
  local waited=0
  until pmset -g batt | grep -q 'AC Power'; do
    [ $waited -eq 0 ] && log "AC 이탈 감지. 복귀 대기"
    sleep 120; waited=$((waited+120))
    [ $waited -ge 43200 ] && { log "AC 12시간 미복귀. 중단"; exit 1; }
  done
  [ $waited -gt 0 ] && log "AC 복귀(${waited}s 대기)"
}
preflight_retry() {
  local deadline="$1"
  while :; do
    colima stop >/dev/null 2>&1; pkill -f 'hugo server' 2>/dev/null
    if "$DIR/preflight_rv.sh"; then return 0; fi
    log "사전 점검 실패. 10분 후 재시도 (사용자 앱은 닫힐 때까지 대기)"
    [ "$(date '+%H%M')" -ge "$deadline" ] && { log "재시도 마감($deadline) 초과. 중단"; return 1; }
    sleep 600
  done
}
PREV="$STUDY/runs/.rv8-ckpt-listcost"
log "체인8 완료 대기 ($PREV)"
while [ ! -f "$PREV" ]; do
  pgrep -f chain_rv8.sh >/dev/null || { log "체인8 프로세스 없음 + 체크포인트 없음. 중단"; exit 1; }
  sleep 60
done
log "체인8 완료 확인"; sleep 120
preflight_retry 0700 || { log "사전 점검 마감 초과. 중단"; exit 1; }
# 상주 환경 확인: 게이트웨이 v1.5.0 + mcp-b 스모크
GW=$(kubectl --context $CTX -n agentgateway-system get gateway agentgateway-proxy -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
code=$(curl -s --max-time 8 -o /dev/null -w "%{http_code}" -X POST "http://$GW/b" \
  -H 'Accept: application/json, text/event-stream' -H 'Content-Type: application/json' \
  -H 'MCP-Protocol-Version: 2026-07-28' -H 'Mcp-Method: tools/call' -H 'Mcp-Name: echo' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo","arguments":{"message":"s"},"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"pf","version":"0.1"},"io.modelcontextprotocol/clientCapabilities":{}}}}')
[ "$code" = "200" ] || { log "스모크 실패(HTTP $code). 중단"; exit 1; }
kubectl --context $CTX -n mcp-pilot get agentgatewaypolicy -o name 2>/dev/null | grep -q . && { log "잔여 정책 있음. 중단"; exit 1; }
log "환경 확인 (GW=$GW, 스모크 200, 정책 0)"
run_stage() { # run_stage <키> <이름> <명령...>
  local key="$1" name="$2"; shift 2
  if [ -f "$CKPT-$key" ]; then log "=== 단계 건너뜀(완료 체크포인트): $name ==="; return 0; fi
  wait_ac
  log "=== 단계 시작: $name ==="
  ( cd "$STUDY" && "$@" ); local rc=$?
  if [ $rc -ne 0 ]; then log "=== 단계 실패($rc): $name. 체인 중단 ==="; push "단계 실패 $name"; exit $rc; fi
  touch "$CKPT-$key"
  log "=== 단계 완료: $name ==="; push "단계 완료 $name"
}
run_stage mixedsus "혼합 30분 close 귀속"  env RV_SUS_ARMS="direct gw" ./harness/rv_mixed_sus.sh "$PY" runs/rv-mixedsus-0905
log "=== 체인9 전체 종료 ==="
