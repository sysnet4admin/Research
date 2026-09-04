#!/usr/bin/env bash
# [rv 사본] g3_spike.sh의 결정론 프로브를 v1.5.0 + aaif-benchmark 상주 환경에서
# 재확인한다(설치/제거 없음, CTX 교체). FailOpen 프로브(weekend-0820 2부)를 덧붙였다.
# 사용: ./rv_g3.sh <OUT_DIR>
set -uo pipefail

OUT="$1"; CTX="aaif-benchmark"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
GRDIR="$STUDY/k8s/guardrail"
mkdir -p "$OUT"
log() { echo "[$(date '+%m-%d %H:%M')] $*"; }
note() { echo "$*" >> "$OUT/FINDINGS.md"; }

GW=$(kubectl --context $CTX -n agentgateway-system get gateway agentgateway-proxy -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
[ -z "$GW" ] && { log "[중단] 게이트웨이 주소 없음"; exit 1; }
GW="http://$GW"
kubectl --context $CTX -n $NS get agentgatewaypolicy -o name 2>/dev/null | grep -q . && { log "[중단] 잔여 정책 있음"; exit 1; }
AGWV=$(kubectl --context $CTX -n agentgateway-system get deploy agentgateway-proxy -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | sed 's/.*://')

echo "# guardrail 결정론 프로브 재확인 (자동 생성, $AGWV)" > "$OUT/FINDINGS.md"
note ""
note "실행 $(date '+%Y-%m-%d %H:%M'). 컨텍스트 $CTX, agentgateway $AGWV. g3-0820(v1.4.1)과 같은 프로브 + FailOpen."
note "guardrail 규칙 = tools/call의 get-sum은 a==1일 때만 허용."
note ""

log "guardrail 서버 배포"
kubectl --context $CTX -n $NS delete configmap guardrail-code >/dev/null 2>&1
kubectl --context $CTX -n $NS create configmap guardrail-code \
  --from-file="$GRDIR/server.py" --from-file="$GRDIR/ext_mcp_pb2.py" \
  --from-file="$GRDIR/ext_mcp_pb2_grpc.py" > "$OUT/install.log" 2>&1
kubectl --context $CTX apply -f "$GRDIR/guardrail.yaml" >> "$OUT/install.log" 2>&1
kubectl --context $CTX -n $NS rollout status deploy/guardrail --timeout=300s >> "$OUT/install.log" 2>&1 \
  || { log "[중단] guardrail 기동 실패"; note "**중단**: guardrail 기동 실패"; exit 1; }
sleep 15
log "GW=$GW"

call() { # call <tool> <args-json>
  curl -s -w '\nHTTP %{http_code}' -X POST "$GW/b" \
    -H 'Accept: application/json, text/event-stream' \
    -H 'Content-Type: application/json' \
    -H 'MCP-Protocol-Version: 2026-07-28' \
    -H 'Mcp-Method: tools/call' \
    -H "Mcp-Name: $1" \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"'$1'","arguments":'$2',"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"g3","version":"0.1"},"io.modelcontextprotocol/clientCapabilities":{}}}}' \
    | head -c 400 | tr '\n' ' '
  echo
}
tools_list() {
  curl -s -w '\nHTTP %{http_code}' -X POST "$GW/b" \
    -H 'Accept: application/json, text/event-stream' \
    -H 'Content-Type: application/json' \
    -H 'MCP-Protocol-Version: 2026-07-28' \
    -H 'Mcp-Method: tools/list' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"g3","version":"0.1"},"io.modelcontextprotocol/clientCapabilities":{}}}}' \
    | head -c 300 | tr '\n' ' '
  echo
}
apply_gr() { # apply_gr <failureMode>
  cat <<YAML | kubectl --context $CTX apply -f - >> "$OUT/install.log" 2>&1
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata:
  name: g3-guardrail
  namespace: mcp-pilot
spec:
  targetRefs:
    - group: agentgateway.dev
      kind: AgentgatewayBackend
      name: mcp-b-stateless
  backend:
    mcp:
      guardrails:
        processors:
          - methods:
              tools/call: Request
            remote:
              backendRef:
                kind: Service
                name: guardrail
                namespace: mcp-pilot
                port: 50051
              failureMode: $1
YAML
  sleep 12
}

note "## G3-0. 정책 없음 기준선"
note "- get-sum a=2: \`$(call get-sum '{"a":2,"b":2}')\` (정책 없으면 통과해야 함)"
note ""

log "mcpGuardrails 정책 적용 (FailClosed)"
apply_gr FailClosed
G3_STATE=$(kubectl --context $CTX -n $NS get agentgatewaypolicy g3-guardrail \
  -o jsonpath='{.status.ancestors[0].conditions[*].type}={.status.ancestors[0].conditions[*].status}' 2>/dev/null)
note "## G3-1. 인자 단위 통제 (정책 status: \`${G3_STATE:-없음}\`)"
note ""
note "- get-sum a=1 (허용 기대): \`$(call get-sum '{"a":1,"b":2}')\`"
note "- get-sum a=2 (거부 기대): \`$(call get-sum '{"a":2,"b":2}')\`"
note "- echo (통과 기대): \`$(call echo '{"message":"ping"}')\`"
note "- tools/list (methods 밖, 정상 기대): \`$(tools_list)\`"
note ""
note "## G3-2. guardrail 서버 로그 (인자 수신과 결정 증거)"
note '```'
kubectl --context $CTX -n $NS logs deploy/guardrail --tail=12 >> "$OUT/FINDINGS.md" 2>/dev/null
note '```'
note ""

log "G3-4: guardrail 0으로 줄여 FailClosed 확인"
kubectl --context $CTX -n $NS scale deploy/guardrail --replicas=0 >/dev/null 2>&1
sleep 20
note "## G3-4. guardrail 서버 부재 시 (failureMode: FailClosed)"
note "- get-sum a=1: \`$(call get-sum '{"a":1,"b":2}')\`"
note "- echo: \`$(call echo '{"message":"ping"}')\`"
note "- tools/list: \`$(tools_list)\`"
note ""

log "G3-5: FailOpen 확인 (서버 부재 유지)"
kubectl --context $CTX -n $NS delete agentgatewaypolicy g3-guardrail >/dev/null 2>&1; sleep 8
apply_gr FailOpen
note "## G3-5. guardrail 서버 부재 시 (failureMode: FailOpen)"
note "- get-sum a=2 (통과 기대): \`$(call get-sum '{"a":2,"b":2}')\`"
note ""
note "판정 기준: FailClosed면 tools/call이 전부 거부되고 tools/list는 무영향. FailOpen이면 a=2가 통과."

log "정리"
kubectl --context $CTX -n $NS delete agentgatewaypolicy g3-guardrail >/dev/null 2>&1
kubectl --context $CTX delete -f "$GRDIR/guardrail.yaml" >/dev/null 2>&1
kubectl --context $CTX -n $NS delete configmap guardrail-code >/dev/null 2>&1
sleep 8
note "- (원복 확인) 정책 제거 후 get-sum a=2: \`$(call get-sum '{"a":2,"b":2}')\`"
note ""
note "---"
note "정리 완료. guardrail 서버와 정책을 제거했다(게이트웨이는 상주)."
log "=== 완료: $OUT ==="
