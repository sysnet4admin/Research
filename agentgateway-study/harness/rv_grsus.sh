#!/usr/bin/env bash
# guardrail 지속 창 (2026-09-04): 게이트웨이 + guardrail 상주 상태에서 정책 유무를
# 바꿔 가며 RV_SUSTAIN초 연속 창을 잰다. off close, on close, on reuse, off reuse 순
# (ABBA). rv_g3.sh(배포)와 rv_gr_matrix.sh(정책 토글)의 최소 델타.
# 사용: ./rv_grsus.sh <PYTHON> <OUT_DIR>
set -uo pipefail
PY="$1"; OUT="$2"
CTX="aaif-benchmark"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
REPO="$(cd "$STUDY/.." && pwd)"
LOADGEN="$REPO/mcp-migration/studies/stateless-scaleout/harness/loadgen.py"
GRDIR="$STUDY/k8s/guardrail"
SUSTAIN="${RV_SUSTAIN:-1800}"
CD="${RV_COOLDOWN:-120}"
RPS=100
mkdir -p "$OUT"
log() { echo "[$(date '+%m-%d %H:%M')] $*"; }
note() { echo "$*" >> "$OUT/FINDINGS.md"; }

"$PY" -c "import httpx" 2>/dev/null || { log "[중단] venv httpx 없음"; exit 1; }
GW=$(kubectl --context $CTX -n agentgateway-system get gateway agentgateway-proxy -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
[ -z "$GW" ] && { log "[중단] 게이트웨이 주소 없음"; exit 1; }
kubectl --context $CTX -n $NS get agentgatewaypolicy -o name 2>/dev/null | grep -q . && { log "[중단] 잔여 정책 있음"; exit 1; }
GW_URL="http://$GW/b"

log "guardrail 서버 배포"
kubectl --context $CTX -n $NS delete configmap guardrail-code >/dev/null 2>&1
kubectl --context $CTX -n $NS create configmap guardrail-code \
  --from-file="$GRDIR/server.py" --from-file="$GRDIR/ext_mcp_pb2.py" \
  --from-file="$GRDIR/ext_mcp_pb2_grpc.py" > "$OUT/install.log" 2>&1
kubectl --context $CTX apply -f "$GRDIR/guardrail.yaml" >> "$OUT/install.log" 2>&1
kubectl --context $CTX -n $NS rollout status deploy/guardrail --timeout=300s >> "$OUT/install.log" 2>&1 \
  || { log "[중단] guardrail 기동 실패"; exit 1; }
sleep 15

policy_on() {
  cat <<YAML | kubectl --context $CTX apply -f - >> "$OUT/install.log" 2>&1
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata:
  name: grsus-guardrail
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
  for i in 1 2 3 4 5; do curl -s --max-time 8 -o /dev/null -X POST "$GW_URL" \
    -H 'Accept: application/json, text/event-stream' -H 'Content-Type: application/json' \
    -H 'MCP-Protocol-Version: 2026-07-28' -H 'Mcp-Method: tools/call' -H 'Mcp-Name: echo' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo","arguments":{"message":"w"},"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"w","version":"0.1"},"io.modelcontextprotocol/clientCapabilities":{}}}}'; done
}
policy_off() { kubectl --context $CTX -n $NS delete agentgatewaypolicy grsus-guardrail >/dev/null 2>&1; sleep 12; }
cell() { # cell <name> <mode>
  "$PY" "$LOADGEN" --url "$GW_URL" --dialect b --tool echo --concurrency 8 --duration "$SUSTAIN" \
    --conn-mode "$2" --rps "$RPS" --out "$OUT/$1.json" >/dev/null 2>&1
  "$PY" -c "
import json
d=json.load(open('$OUT/$1.json'))
err=sum(d.get('errors', {}).values())
print(f\"achieved={d['achieved_rps']:.1f} p50={d['latency_ms']['p50']:.1f} p99={d['latency_ms']['p99']:.1f} err={err} shed={d.get('shed',0)} gwerr={d.get('gateway_error',0)}\")"
}

echo "# guardrail 지속 창 ${SUSTAIN}초 (자동 생성)" > "$OUT/FINDINGS.md"
note ""
note "실행 $(date '+%Y-%m-%d %H:%M'). gw=\`$GW_URL\`, ${RPS}rps conc 8. 순서 off close -> on close -> on reuse -> off reuse, 셀 간 ${CD}초."
note "- 전원: $(pmset -g batt | head -1 | sed "s/Now drawing from //")"
note ""
for spec in "off close" "on close" "on reuse" "off reuse"; do
  set -- $spec; st="$1"; mode="$2"
  [ "$st" = on ] && policy_on || policy_off
  log "=== 지속 ${st} ${mode} (${SUSTAIN}s) ==="
  R=$(cell "grsus-${st}-${mode}" "$mode")
  note "  - ${st} ${mode}: $R"
  sleep "$CD"
done
policy_off
log "정리: guardrail 제거"
kubectl --context $CTX delete -f "$GRDIR/guardrail.yaml" >> "$OUT/install.log" 2>&1
kubectl --context $CTX -n $NS delete configmap guardrail-code >> "$OUT/install.log" 2>&1
note ""
note "---"
note "종료 $(date '+%Y-%m-%d %H:%M'). guardrail 서버와 정책을 제거했다(게이트웨이 상주)."
log "=== guardrail 지속 창 완료: $OUT ==="
