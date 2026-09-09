#!/usr/bin/env bash
# extAuth / extProc 결정론 프로브만 (지연 셀 없음). 원고 작업과 병행 가능.
# 보는 것: 강제 여부, 거부 응답의 모양(코드와 본문), 검사 서버 부재 시 FailClosed/FailOpen.
# 비용 측정은 rv_ext.sh가 무인 창에서 따로 한다.
# 사용: ./rv_extdet.sh <OUT_DIR>
set -uo pipefail

OUT_REL="$1"
CTX="aaif-benchmark"; NS="mcp-pilot"; AGWNS="agentgateway-system"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
BIN="$STUDY/k8s/extproc/extproc-linux-arm64"
OUT="$STUDY/$OUT_REL"; mkdir -p "$OUT"
log() { echo "[extdet $(date '+%m-%d %H:%M')] $*"; }
note() { echo "$*" >> "$OUT/FINDINGS.md"; }

GW=$(kubectl --context $CTX -n $AGWNS get gateway agentgateway-proxy -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
[ -z "$GW" ] && { log "[중단] 게이트웨이 주소 없음"; exit 1; }
AGWV=$(kubectl --context $CTX -n $AGWNS get deploy agentgateway-proxy -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | sed 's/.*://')

echo "# extAuth / extProc 결정론 프로브 (자동 생성, agentgateway $AGWV)" > "$OUT/FINDINGS.md"
note ""
note "실행 $(date '+%Y-%m-%d %H:%M'). 규칙은 결과 7과 같다: tools/call get-sum은 a == 1일 때만 허용."
note "지연은 재지 않는다(무인 창의 rv_ext.sh 몫). 여기서는 강제 여부와 거부 모양만 본다."
note ""

call() { # call <tag> <tool> <args-json>  -> "HTTP <code> <본문 앞부분>"
  local tag="$1" tool="$2" args="$3" code
  code=$(curl -s --max-time 8 -o "$OUT/$tag.json" -w "%{http_code}" -X POST "http://$GW/b" \
    -H 'Accept: application/json, text/event-stream' -H 'Content-Type: application/json' \
    -H 'MCP-Protocol-Version: 2026-07-28' -H 'Mcp-Method: tools/call' -H "Mcp-Name: $tool" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"$tool\",\"arguments\":$args,\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\",\"io.modelcontextprotocol/clientInfo\":{\"name\":\"extdet\",\"version\":\"0.1\"},\"io.modelcontextprotocol/clientCapabilities\":{}}}}")
  echo "HTTP $code $(head -c 150 "$OUT/$tag.json" | tr '\n' ' ')"
}
list_tools() { local code
  code=$(curl -s --max-time 8 -o "$OUT/$1.json" -w "%{http_code}" -X POST "http://$GW/b" \
    -H 'Accept: application/json, text/event-stream' -H 'Content-Type: application/json' \
    -H 'MCP-Protocol-Version: 2026-07-28' -H 'Mcp-Method: tools/list' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"extdet","version":"0.1"},"io.modelcontextprotocol/clientCapabilities":{}}}}')
  echo "HTTP $code tools=$(grep -o '\"name\":' "$OUT/$1.json" | wc -l | tr -d ' ')"
}
probe_round() { # probe_round <prefix>
  local p="$1"
  note "- $p get-sum a=1 (통과 기대): \`$(call "$p-a1" get-sum '{"a":1,"b":2}')\`"
  note "- $p get-sum a=2 (거부 기대): \`$(call "$p-a2" get-sum '{"a":2,"b":2}')\`"
  note "- $p echo (통과 기대): \`$(call "$p-echo" echo '{"message":"x"}')\`"
  note "- $p tools/list: \`$(list_tools "$p-list")\`"
}
del_policy() { kubectl --context $CTX -n $NS delete agentgatewaypolicy rv-extdet >/dev/null 2>&1; sleep 8; }
pstatus() { kubectl --context $CTX -n $NS get agentgatewaypolicy rv-extdet -o jsonpath='Accepted={.status.ancestors[0].conditions[?(@.type=="Accepted")].status}({.status.ancestors[0].conditions[?(@.type=="Accepted")].reason}) Attached={.status.ancestors[0].conditions[?(@.type=="Attached")].status}' 2>/dev/null; }
apply_extauth() { # apply_extauth <failureMode>
  cat <<YAML | kubectl --context $CTX apply -f - >> "$OUT/apply.log" 2>&1
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata: { name: rv-extdet, namespace: mcp-pilot }
spec:
  targetRefs:
    - { group: gateway.networking.k8s.io, kind: HTTPRoute, name: mcp-b }
  traffic:
    extAuth:
      backendRef: { kind: Service, name: extauth, namespace: mcp-pilot, port: 8000 }
      failureMode: $1
      http:
        path: '"/check"'
        body: '{"body": string(request.body)}'
YAML
  sleep 12
}
apply_extproc() { # apply_extproc <failureMode>
  cat <<YAML | kubectl --context $CTX apply -f - >> "$OUT/apply.log" 2>&1
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata: { name: rv-extdet, namespace: mcp-pilot }
spec:
  targetRefs:
    - { group: gateway.networking.k8s.io, kind: HTTPRoute, name: mcp-b }
  traffic:
    extProc:
      backendRef: { kind: Service, name: extproc, namespace: mcp-pilot, port: 18080 }
      failureMode: $1
      processingOptions:
        requestBodyMode: Buffered
        requestHeaderMode: Send
        responseBodyMode: None
        responseHeaderMode: Skip
YAML
  sleep 12
}
cleanup() {
  del_policy
  kubectl --context $CTX delete -f "$STUDY/k8s/extauth/extauth.yaml" >/dev/null 2>&1
  kubectl --context $CTX -n $NS delete configmap extauth-code >/dev/null 2>&1
  kubectl --context $CTX delete -f "$STUDY/k8s/extproc/extproc.yaml" >/dev/null 2>&1
  log "정리 완료"
}
trap cleanup EXIT

log "extAuth 서버 배포"
kubectl --context $CTX -n $NS delete configmap extauth-code >/dev/null 2>&1
kubectl --context $CTX -n $NS create configmap extauth-code --from-file="$STUDY/k8s/extauth/server.py" > "$OUT/apply.log" 2>&1
kubectl --context $CTX apply -f "$STUDY/k8s/extauth/extauth.yaml" >> "$OUT/apply.log" 2>&1
kubectl --context $CTX -n $NS rollout status deploy/extauth --timeout=300s >> "$OUT/apply.log" 2>&1 || { note "**중단**: extauth 기동 실패"; exit 1; }

if [ -x "$BIN" ]; then
  log "extProc 서버 배포"
  kubectl --context $CTX apply -f "$STUDY/k8s/extproc/extproc.yaml" >> "$OUT/apply.log" 2>&1
  sleep 10
  POD=$(kubectl --context $CTX -n $NS get pod -l app=extproc -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  kubectl --context $CTX -n $NS wait --for=condition=Ready "pod/$POD" --timeout=180s >> "$OUT/apply.log" 2>&1
  kubectl --context $CTX -n $NS cp "$BIN" "$POD:/work/extproc" >> "$OUT/apply.log" 2>&1
  sleep 15
else
  log "extProc 바이너리 없음, extAuth만 진행"
fi

note "## 0. 정책 없음 기준선"
probe_round base
note ""

for arm in extauth extproc; do
  [ "$arm" = extproc ] && [ ! -x "$BIN" ] && continue
  note "## $arm"
  note ""
  log "$arm FailClosed 적용"
  if [ "$arm" = extauth ]; then apply_extauth FailClosed; else apply_extproc FailClosed; fi
  note "### 정책 적용 (상태: \`$(pstatus)\`)"
  probe_round "$arm-on"
  note ""
  note "거부 응답 원문(a=2), 헤더 포함:"
  note '```'
  curl -s -i --max-time 8 -X POST "http://$GW/b" \
    -H 'Accept: application/json, text/event-stream' -H 'Content-Type: application/json' \
    -H 'MCP-Protocol-Version: 2026-07-28' -H 'Mcp-Method: tools/call' -H 'Mcp-Name: get-sum' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get-sum","arguments":{"a":2,"b":2},"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"extdet","version":"0.1"},"io.modelcontextprotocol/clientCapabilities":{}}}}' \
    | head -c 700 >> "$OUT/FINDINGS.md" 2>&1
  note ""
  note '```'
  note ""
  note "검사 서버 로그(마지막 6줄):"
  note '```'
  kubectl --context $CTX -n $NS logs "deploy/$arm" --tail=6 >> "$OUT/FINDINGS.md" 2>&1
  note '```'
  note ""
  log "$arm 검사 서버 0으로 줄여 FailClosed 확인"
  kubectl --context $CTX -n $NS scale "deploy/$arm" --replicas=0 >/dev/null 2>&1
  sleep 20
  note "### 검사 서버 부재, FailClosed"
  probe_round "$arm-closed"
  note ""
  log "$arm FailOpen 확인 (서버 부재 유지)"
  del_policy
  if [ "$arm" = extauth ]; then apply_extauth FailOpen; else apply_extproc FailOpen; fi
  note "### 검사 서버 부재, FailOpen (상태: \`$(pstatus)\`)"
  probe_round "$arm-open"
  note ""
  kubectl --context $CTX -n $NS scale "deploy/$arm" --replicas=1 >/dev/null 2>&1
  kubectl --context $CTX -n $NS rollout status "deploy/$arm" --timeout=180s >> "$OUT/apply.log" 2>&1
  if [ "$arm" = extproc ]; then
    POD=$(kubectl --context $CTX -n $NS get pod -l app=extproc -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    kubectl --context $CTX -n $NS cp "$BIN" "$POD:/work/extproc" >> "$OUT/apply.log" 2>&1
    sleep 15
  fi
  del_policy
  note "- (원복 확인) get-sum a=2: \`$(call "$arm-clean" get-sum '{"a":2,"b":2}')\`"
  note ""
done

note "---"
note "판정 기준: a=1 통과 + a=2 거부면 그 경로로 인자 통제가 된다. 거부 모양은 결과 7의"
note "가드레일(HTTP 200 + JSON-RPC -32001 + 사유 문자열)과 견준다."
log "=== rv_extdet 완료: $OUT ==="
