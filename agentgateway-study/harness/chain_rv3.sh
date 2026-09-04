#!/usr/bin/env bash
# rv 재측정 최종 체인 (2026-08-31 18:00 기동, 무간섭 조건. 오늘 낮 측정분은
# 전량 폐기하고 이 체인이 정본을 만든다).
# 구성: 18:00 대기 -> 사전 점검 -> [0] 환경 재초기화(베이스라인 복원 + 재배포)
#  -> [1] MCP 축 -> [2] A2A 프로브 -> [3] 경로 쌍 -> [4] guardrail 교대
#  -> [5] A2A 3팔 20회차. 단계 실패 시 중단. 예상 종료 9/1(월... 화) 오전.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
REPO="$(cd "$STUDY/.." && pwd)"
A2A="$REPO/a2a-study"
CLUSTER="$STUDY/test-cluster"
CTX="aaif-benchmark"
PY="$HOME/.venvs/mcpbench/bin/python"
log() { echo "[chain3 $(date '+%m-%d %H:%M')] $*"; }
push() { ( cd "$REPO" && git add agentgateway-study/runs a2a-study/runs >/dev/null 2>&1 \
  && git commit -q -m "rv 체인3: $1" >/dev/null 2>&1 \
  && git pull --rebase --autostash -q origin main >/dev/null 2>&1 \
  && git push -q origin main >/dev/null 2>&1 ) || true; }
run_stage() {
  local name="$1" wd="$2"; shift 2
  pmset -g batt | grep -q 'AC Power' || { log "AC 이탈 감지. 중단"; push "AC 이탈로 중단"; exit 1; }
  log "=== 단계 시작: $name ==="
  ( cd "$wd" && "$@" ); local rc=$?
  if [ $rc -ne 0 ]; then log "=== 단계 실패($rc): $name. 체인 중단 ==="; push "단계 실패 $name"; exit $rc; fi
  log "=== 단계 완료: $name ==="; push "단계 완료 $name"
}

log "18:00 대기 시작"
while [ "$(date '+%H%M')" -lt 1800 ]; do sleep 60; done
log "18:00 도달. 사전 점검"
"$DIR/preflight_rv.sh" || { log "사전 점검 실패. 기동 중단"; exit 1; }

log "=== [0] 환경 재초기화 ==="
( cd "$CLUSTER" && ./reset.sh ) || { log "베이스라인 복원 실패"; exit 1; }
sleep 20
for i in $(seq 1 30); do
  [ "$(kubectl --context $CTX get nodes --no-headers 2>/dev/null | grep -c ' Ready')" -eq 3 ] && break; sleep 10
done
"$DIR/deploy_backends.sh" || { log "백엔드 배포 실패"; exit 1; }
AGW_VER=v1.5.0 "$DIR/install_agw.sh" || { log "게이트웨이 설치 실패"; exit 1; }
sleep 10
GW=$(kubectl --context $CTX -n agentgateway-system get gateway agentgateway-proxy -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
CODE=$(curl -s --max-time 8 -o /dev/null -w "%{http_code}" -X POST "http://$GW/b" \
  -H 'Accept: application/json, text/event-stream' -H 'Content-Type: application/json' \
  -H 'MCP-Protocol-Version: 2026-07-28' -H 'Mcp-Method: tools/call' -H 'Mcp-Name: echo' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo","arguments":{"message":"s"},"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"pf","version":"0.1"},"io.modelcontextprotocol/clientCapabilities":{}}}}')
[ "$CODE" = "200" ] || { log "스모크 실패(HTTP $CODE). 중단"; exit 1; }
log "=== [0] 완료 (GW=$GW, 스모크 200) ==="
push "환경 재초기화 완료"

run_stage "MCP 축"          "$STUDY" ./harness/rv_run_axes.sh "$PY" runs/rv-axes-0831e
run_stage "A2A 프로브"      "$A2A"   ./harness/rv_probes.sh runs/rv-probes-0831e
run_stage "경로 쌍"         "$STUDY" ./harness/rv_run_ab.sh "$PY" runs/rv-ab-0831e
run_stage "guardrail 교대"  "$STUDY" ./harness/rv_gr_matrix.sh runs/rv-grm-0831e
run_stage "A2A 3팔 20회차"  "$A2A"   ./harness/rv_ab_matrix.sh runs/rv-abm-0831e 1 20
log "=== 체인3 전체 종료 ==="
push "체인3 전체 종료"
