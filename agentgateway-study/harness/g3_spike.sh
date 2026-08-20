#!/usr/bin/env bash
# 축 3 스파이크: mcpGuardrails(ExtMcp gRPC)로 인자 단위 통제가 실제로 되는가.
#
# 확인 항목:
#   G3-1 guardrail 정책("get-sum은 a==1만") 아래에서 a=1 통과 / a=2 거부 / echo 통과
#   G3-2 거부의 표면 형태(상태 코드, JSON-RPC 오류)와 guardrail 서버 로그(인자 수신 증거)
#   G3-3 tools/list는 methods 매칭 밖이라 정상 동작하는가
#   G3-4 FailClosed: guardrail 서버를 0으로 줄이면 tools/call이 거부되는가
#
# 사용: ./g3_spike.sh <OUT_DIR>
set -uo pipefail

OUT="$1"; CTX="mcp-migration"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
MCPSTUDY="$(cd "$DIR/../../mcp-migration/studies/stateless-scaleout" && pwd)"
GWDIR="$MCPSTUDY/k8s/agentgateway"
GRDIR="$STUDY/k8s/guardrail"
mkdir -p "$OUT"
log() { echo "[$(date '+%m-%d %H:%M')] $*"; }
note() { echo "$*" >> "$OUT/FINDINGS.md"; }

echo "# 축 3 스파이크: mcpGuardrails 인자 통제 (자동 생성)" > "$OUT/FINDINGS.md"
note ""
note "실행 $(date '+%Y-%m-%d %H:%M'). guardrail 규칙 = tools/call의 get-sum은 a==1일 때만 허용."
note ""

# ── 준비: 게이트웨이 + guardrail 서버 ────────────────────────────────
log "agentgateway v1.4.1 설치"
AGW_VER=v1.4.1 bash "$GWDIR/install.sh" > "$OUT/install.log" 2>&1
sleep 30
kubectl --context $CTX apply -f "$GWDIR/gateway.yaml" >> "$OUT/install.log" 2>&1

log "guardrail 서버 배포"
kubectl --context $CTX -n $NS delete configmap guardrail-code >/dev/null 2>&1
kubectl --context $CTX -n $NS create configmap guardrail-code \
  --from-file="$GRDIR/server.py" --from-file="$GRDIR/ext_mcp_pb2.py" \
  --from-file="$GRDIR/ext_mcp_pb2_grpc.py" >> "$OUT/install.log" 2>&1
kubectl --context $CTX apply -f "$GRDIR/guardrail.yaml" >> "$OUT/install.log" 2>&1
kubectl --context $CTX -n $NS rollout status deploy/guardrail --timeout=300s >> "$OUT/install.log" 2>&1 \
  || { log "[중단] guardrail 기동 실패"; note "**중단**: guardrail 기동 실패"; exit 1; }
sleep 15
GW=$(kubectl --context $CTX -n agentgateway-system get gateway agentgateway-proxy -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
[ -z "$GW" ] && { log "[중단] 게이트웨이 주소 없음"; exit 1; }
GW="http://$GW"
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

# ── 기준선: guardrail 정책 없이 ──────────────────────────────────────
note "## G3-0. 정책 없음 기준선"
note "- get-sum a=2: \`$(call get-sum '{"a":2,"b":2}')\` (정책 없으면 통과해야 함)"
note ""

# ── guardrails 정책 적용 ─────────────────────────────────────────────
log "mcpGuardrails 정책 적용"
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
              failureMode: FailClosed
YAML
sleep 12
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

# ── FailClosed 확인 ──────────────────────────────────────────────────
log "G3-4: guardrail 0으로 줄여 FailClosed 확인"
kubectl --context $CTX -n $NS scale deploy/guardrail --replicas=0 >/dev/null 2>&1
sleep 20
note "## G3-4. guardrail 서버 부재 시 (failureMode: FailClosed)"
note "- get-sum a=1: \`$(call get-sum '{"a":1,"b":2}')\`"
note "- echo: \`$(call echo '{"message":"ping"}')\`"
note ""
note "판정 기준: FailClosed면 tools/call이 전부 거부되어야 한다. tools/list는"
note "methods 밖이라 영향이 없어야 한다."
note "- tools/list: \`$(tools_list)\`"
kubectl --context $CTX -n $NS scale deploy/guardrail --replicas=1 >/dev/null 2>&1

# ── 정리 ─────────────────────────────────────────────────────────────
log "정리"
kubectl --context $CTX -n $NS delete agentgatewaypolicy g3-guardrail >/dev/null 2>&1
kubectl --context $CTX delete -f "$GRDIR/guardrail.yaml" >/dev/null 2>&1
kubectl --context $CTX -n $NS delete configmap guardrail-code >/dev/null 2>&1
bash "$GWDIR/uninstall.sh" >> "$OUT/install.log" 2>&1
note ""
note "---"
note "정리 완료. guardrail과 게이트웨이를 제거해 격리 상태로 되돌렸다."
log "=== 축 3 스파이크 완료: $OUT ==="
