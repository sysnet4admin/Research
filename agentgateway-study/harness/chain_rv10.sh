#!/usr/bin/env bash
# rv 체인10 (2026-09-09): 트레이싱 켠 경로 -> extAuth/extProc 인자 통제.
# chain_rv9.sh의 최소 델타 사본(단계 2개). 상주 환경(v1.5.0 게이트웨이, mcp-b) 재사용.
# 사용: caffeinate -i nohup ./chain_rv10.sh > /tmp/rv-chain10.log 2>&1 & disown
# 조절: RV_START(기동 대기 시각 HHMM, 미지정이면 즉시) RV_ROUNDS RV_DURATION RV_COOLDOWN
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
REPO="$(cd "$STUDY/.." && pwd)"
CTX="aaif-benchmark"
PY="$HOME/.venvs/mcpbench/bin/python"
CKPT="$STUDY/runs/.rv10-ckpt"
log() { echo "[chain10 $(date '+%m-%d %H:%M')] $*"; }
push() { ( cd "$REPO" && git add agentgateway-study/runs >/dev/null 2>&1 \
  && git commit -q -m "rv 체인10: $1" >/dev/null 2>&1 \
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
[ -n "${RV_START:-}" ] && { log "기동 대기 $RV_START"; wait_until "$RV_START"; }
preflight_retry "${RV_DEADLINE:-0500}" || { log "사전 점검 마감 초과. 중단"; exit 1; }

# 상주 환경 확인
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
STAMP="${RV_STAMP:-$(date '+%m%d')}"
run_stage trace "트레이싱 켠 경로"      ./harness/rv_trace.sh "$PY" "runs/rv-trace-$STAMP"
run_stage ext   "extAuth/extProc 인자 통제" ./harness/rv_ext.sh  "$PY" "runs/rv-ext-$STAMP"
log "=== 체인10 전체 종료 ==="
