#!/usr/bin/env bash
# rv 재측정 오케스트레이터 v4 (2026-09-02. 무인 작업 원칙 적용판).
# 흐름: 11:30 리허설(축소판 전 단계 완주) -> 통과 시 18:00 본 창 -> 5단계.
# 원칙 반영: (2) 리허설, (3) 재시도 게이트 + 단계 체크포인트 + AC 대기-재개.
# 사용: caffeinate -i nohup ./chain_rv4.sh > /tmp/rv-chain4.log 2>&1 &
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
REPO="$(cd "$STUDY/.." && pwd)"
A2A="$REPO/a2a-study"
CLUSTER="$STUDY/test-cluster"
CTX="aaif-benchmark"
PY="$HOME/.venvs/mcpbench/bin/python"
CKPT="$STUDY/runs/.rv4-ckpt"
log() { echo "[chain4 $(date '+%m-%d %H:%M')] $*"; }
push() { ( cd "$REPO" && git add agentgateway-study/runs a2a-study/runs >/dev/null 2>&1 \
  && git commit -q -m "rv 체인4: $1" >/dev/null 2>&1 \
  && git pull --rebase --autostash -q origin main >/dev/null 2>&1 \
  && git push -q origin main >/dev/null 2>&1 ) || true; }

wait_until() { # wait_until HHMM
  while [ "$(date '+%H%M')" -lt "$1" ]; do sleep 60; done
}
wait_ac() { # AC 이탈 시 중단 대신 복귀 대기 (최대 12시간)
  local waited=0
  until pmset -g batt | grep -q 'AC Power'; do
    [ $waited -eq 0 ] && log "AC 이탈 감지. 복귀 대기"
    sleep 120; waited=$((waited+120))
    [ $waited -ge 43200 ] && { log "AC 12시간 미복귀. 중단"; exit 1; }
  done
  [ $waited -gt 0 ] && log "AC 복귀(${waited}s 대기)"
}
preflight_retry() { # 통과할 때까지 10분 간격 재시도 (마감 HHMM까지)
  local deadline="$1"
  while :; do
    colima stop >/dev/null 2>&1; pkill -f 'hugo server' 2>/dev/null  # 내 도구는 자동 정리
    if "$DIR/preflight_rv.sh"; then return 0; fi
    log "사전 점검 실패. 10분 후 재시도 (사용자 앱은 닫힐 때까지 대기)"
    [ "$(date '+%H%M')" -ge "$deadline" ] && { log "재시도 마감($deadline) 초과. 중단"; return 1; }
    sleep 600
  done
}
reinit_env() { # 베이스라인 복원 + 재배포 + 스모크
  ( cd "$CLUSTER" && ./reset.sh ) || return 1
  sleep 20
  for i in $(seq 1 30); do
    [ "$(kubectl --context $CTX get nodes --no-headers 2>/dev/null | grep -c ' Ready')" -eq 3 ] && break; sleep 10
  done
  "$DIR/deploy_backends.sh" || return 1
  AGW_VER=v1.5.0 "$DIR/install_agw.sh" || return 1
  sleep 10
  GW=$(kubectl --context $CTX -n agentgateway-system get gateway agentgateway-proxy -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
  local code
  code=$(curl -s --max-time 8 -o /dev/null -w "%{http_code}" -X POST "http://$GW/b" \
    -H 'Accept: application/json, text/event-stream' -H 'Content-Type: application/json' \
    -H 'MCP-Protocol-Version: 2026-07-28' -H 'Mcp-Method: tools/call' -H 'Mcp-Name: echo' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo","arguments":{"message":"s"},"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"pf","version":"0.1"},"io.modelcontextprotocol/clientCapabilities":{}}}}')
  [ "$code" = "200" ] || { log "스모크 실패(HTTP $code)"; return 1; }
  log "환경 준비 완료 (GW=$GW, 스모크 200)"
}
run_stage() { # run_stage <체크포인트키> <이름> <작업디렉토리> <명령...>
  local key="$1" name="$2" wd="$3"; shift 3
  if [ -f "$CKPT-$key" ]; then log "=== 단계 건너뜀(완료 체크포인트): $name ==="; return 0; fi
  wait_ac
  log "=== 단계 시작: $name ==="
  ( cd "$wd" && "$@" ); local rc=$?
  if [ $rc -ne 0 ]; then log "=== 단계 실패($rc): $name. 체인 중단 ==="; push "단계 실패 $name"; exit $rc; fi
  touch "$CKPT-$key"
  log "=== 단계 완료: $name ==="; push "단계 완료 $name"
}

### 1부: 리허설 (11:30, 축소판 전 단계 완주)
if [ ! -f "$CKPT-rehearsal" ]; then
  log "리허설 대기 (11:30)"
  wait_until 1130
  preflight_retry 1330 || { log "리허설 사전 점검 마감 초과. 전체 중단"; exit 1; }
  log "=== 리허설 시작 (RV_DURATION=5 RV_COOLDOWN=5 RV_ROUNDS=1) ==="
  export RV_DURATION=5 RV_COOLDOWN=5 RV_ROUNDS=1
  reinit_env || { log "리허설: 환경 재초기화 실패"; exit 1; }
  ( cd "$STUDY" && ./harness/rv_run_axes.sh "$PY" runs/rehearsal-0902/axes )   || { log "리허설 실패: MCP 축"; exit 1; }
  ( cd "$A2A"   && ./harness/rv_probes.sh runs/rehearsal-0902/probes )         || { log "리허설 실패: A2A 프로브"; exit 1; }
  ( cd "$STUDY" && ./harness/rv_run_ab.sh "$PY" runs/rehearsal-0902/ab )       || { log "리허설 실패: 경로 쌍"; exit 1; }
  ( cd "$STUDY" && ./harness/rv_gr_matrix.sh runs/rehearsal-0902/grm )         || { log "리허설 실패: guardrail"; exit 1; }
  ( cd "$A2A"   && ./harness/rv_ab_matrix.sh runs/rehearsal-0902/abm 1 1 )     || { log "리허설 실패: A2A 세 경로"; exit 1; }
  unset RV_DURATION RV_COOLDOWN RV_ROUNDS
  touch "$CKPT-rehearsal"
  log "=== 리허설 전 단계 완주. 본 창 대기 ==="
  push "리허설 완주"
fi

### 2부: 본 창 (18:00)
log "본 창 대기 (18:00)"
wait_until 1800
preflight_retry 2330 || { log "본 창 사전 점검 마감 초과. 중단"; exit 1; }
if [ ! -f "$CKPT-reinit" ]; then
  log "=== [0] 환경 재초기화 (리허설 잔재 제거) ==="
  reinit_env || { log "재초기화 실패"; exit 1; }
  touch "$CKPT-reinit"; push "본 창 환경 재초기화"
fi
run_stage axes  "MCP 축"          "$STUDY" ./harness/rv_run_axes.sh "$PY" runs/rv-axes-0902
run_stage probe "A2A 프로브"      "$A2A"   ./harness/rv_probes.sh runs/rv-probes-0902
run_stage ab    "경로 쌍"         "$STUDY" ./harness/rv_run_ab.sh "$PY" runs/rv-ab-0902
run_stage grm   "guardrail 교대"  "$STUDY" ./harness/rv_gr_matrix.sh runs/rv-grm-0902
run_stage abm   "A2A 세 경로 20회차"  "$A2A"   ./harness/rv_ab_matrix.sh runs/rv-abm-0902 1 20
log "=== 체인4 전체 종료 ==="
push "체인4 전체 종료"
