#!/usr/bin/env bash
# P2 보강 프로브 (2026-08-20). 이슈 #3092 외부 검토가 요구한 증거를 모은다.
#   F1 arg-test 정책 아래 tools/list가 비는가 (규칙이 아무것도 매치 못 한 직접 증거)
#   F2 모든 호출의 HTTP 상태 코드 명시 (-w, 전사본에 400 근거 부재 지적)
#   F3 이름 조건 없는 규칙(mcp.tool.arguments.a == 1)의 동작
#   F4 has(mcp.tool.arguments) 가드의 동작 (우회 가능 여부)
#   F5 프록시와 컨트롤 플레인 로그에 CEL 평가 오류가 찍히는가 ("silently"의 근거)
# 사용: ./p2_followup.sh <OUT_DIR>
set -uo pipefail

OUT="$1"; CTX="mcp-migration"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCPSTUDY="$(cd "$DIR/../../mcp-migration/studies/stateless-scaleout" && pwd)"
GWDIR="$MCPSTUDY/k8s/agentgateway"
mkdir -p "$OUT"
log() { echo "[$(date '+%m-%d %H:%M')] $*"; }
note() { echo "$*" >> "$OUT/FINDINGS.md"; }

echo "# P2 보강 프로브 (자동 생성, 이슈 #3092 검토 반영)" > "$OUT/FINDINGS.md"
note ""

log "게이트웨이 설치"
AGW_VER=v1.4.1 bash "$GWDIR/install.sh" > "$OUT/install.log" 2>&1
sleep 30
kubectl --context $CTX apply -f "$GWDIR/gateway.yaml" >> "$OUT/install.log" 2>&1
sleep 15
GW=$(kubectl --context $CTX -n agentgateway-system get gateway agentgateway-proxy -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
[ -z "$GW" ] && { log "[중단] 게이트웨이 주소 없음"; exit 1; }
GW="http://$GW"
log "GW=$GW"

call() { # call <tool> <args-json>  (상태 코드 포함)
  curl -s -w '\nHTTP %{http_code}' -X POST "$GW/b" \
    -H 'Accept: application/json, text/event-stream' \
    -H 'Content-Type: application/json' \
    -H 'MCP-Protocol-Version: 2026-07-28' \
    -H 'Mcp-Method: tools/call' \
    -H "Mcp-Name: $1" \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"'$1'","arguments":'$2',"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"followup","version":"0.1"},"io.modelcontextprotocol/clientCapabilities":{}}}}' \
    | tr '\n' ' '
  echo
}
tools_list() {
  curl -s -w '\nHTTP %{http_code}' -X POST "$GW/b" \
    -H 'Accept: application/json, text/event-stream' \
    -H 'Content-Type: application/json' \
    -H 'MCP-Protocol-Version: 2026-07-28' \
    -H 'Mcp-Method: tools/list' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"followup","version":"0.1"},"io.modelcontextprotocol/clientCapabilities":{}}}}' \
    | head -c 500 | tr '\n' ' '
  echo
}
apply_rule() { # apply_rule <name> <expr>
  cat <<YAML | kubectl --context $CTX apply -f - >/dev/null 2>&1
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata:
  name: $1
  namespace: $NS
spec:
  targetRefs:
    - group: agentgateway.dev
      kind: AgentgatewayBackend
      name: mcp-b-stateless
  backend:
    mcp:
      authorization:
        policy:
          matchExpressions:
            - $2
YAML
  sleep 12
}
drop_rule() { kubectl --context $CTX -n $NS delete agentgatewaypolicy "$1" >/dev/null 2>&1; sleep 8; }
policy_status() {
  kubectl --context $CTX -n $NS get agentgatewaypolicy "$1" -o jsonpath='{.status.ancestors[0].conditions[*].type}={.status.ancestors[0].conditions[*].status}' 2>/dev/null
}

probe_set() { # probe_set <label>
  note "### $1"
  note "- 정책 status: \`$(policy_status ax-f)\`"
  note "- tools/list: \`$(tools_list)\`"
  note "- get-sum a=1: \`$(call get-sum '{"a":1,"b":2}')\`"
  note "- echo: \`$(call echo '{"message":"ping"}')\`"
  note ""
}

# 기준선 (정책 없음)
note "## F0. 정책 없음 기준선"
note "- tools/list: \`$(tools_list)\`"
note "- get-sum a=1: \`$(call get-sum '{"a":1,"b":2}')\`"
note ""

# F1+F2: 원래 arg-test 규칙
log "F1/F2: 원래 규칙 + tools/list + 상태 코드"
note "## F1/F2. 규칙: mcp.tool.name == \"get-sum\" && mcp.tool.arguments.a == 1"
apply_rule ax-f 'mcp.tool.name == "get-sum" && mcp.tool.arguments.a == 1'
probe_set "원래 규칙"
LOG_T0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
call get-sum '{"a":1,"b":2}' >/dev/null
sleep 3
note "### F5a. 위 호출 직후 프록시 로그 (오류 흔적 유무)"
note '```'
kubectl --context $CTX -n agentgateway-system logs deploy/agentgateway-proxy --since-time="$LOG_T0" 2>/dev/null | tail -20 >> "$OUT/FINDINGS.md"
note '```'
note ""
drop_rule ax-f

# F3: 이름 조건 없는 규칙
log "F3: 이름 조건 없는 규칙"
note "## F3. 규칙: mcp.tool.arguments.a == 1 (이름 조건 없음)"
apply_rule ax-f 'mcp.tool.arguments.a == 1'
probe_set "이름 조건 없음"
drop_rule ax-f

# F4: has() 가드
log "F4: has() 가드"
note "## F4. 규칙: has(mcp.tool.arguments) (필드 존재 검사)"
apply_rule ax-f 'has(mcp.tool.arguments)'
probe_set "has 가드"
note "## F4b. 규칙: mcp.tool.name == \"get-sum\" && (!has(mcp.tool.arguments) || mcp.tool.arguments.a == 1)"
drop_rule ax-f
apply_rule ax-f 'mcp.tool.name == "get-sum" && (!has(mcp.tool.arguments) || mcp.tool.arguments.a == 1)'
probe_set "has 부정 가드"
drop_rule ax-f

# F5b: 컨트롤 플레인 로그 (정책 수용 시점 경고 유무)
note "## F5b. 컨트롤 플레인 로그 끝부분 (검증 경고 유무)"
note '```'
kubectl --context $CTX -n agentgateway-system logs deploy/agentgateway --tail=30 2>/dev/null >> "$OUT/FINDINGS.md"
note '```'

log "정리"
bash "$GWDIR/uninstall.sh" >> "$OUT/install.log" 2>&1
note ""
note "정리 완료 (게이트웨이 제거)."
log "=== 보강 프로브 완료: $OUT ==="
