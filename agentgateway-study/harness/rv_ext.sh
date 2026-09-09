#!/usr/bin/env bash
# extAuth와 extProc로 인자 통제가 되는지와 그 비용 (README 한계 "extAuthz/extProc 미검증" 해소).
# 결과 7(mcpGuardrails)과 같은 규칙 "get-sum은 a==1일 때만"을 두 경로로 걸고 비교한다.
#
#  E1. extAuth(HTTP 모드): 표준 라이브러리 파이썬 서버. 200 허용, 403 거부.
#  E2. extProc(gRPC, Envoy ext_proc v3): Go 서버. 거부는 ImmediateResponse 403.
# 각 경로에서 프로브(a=1 통과, a=2 거부, echo 통과, tools/list) 뒤 비용 셀을 잰다.
#
# 사용: ./rv_ext.sh <PYTHON> <OUT_DIR>
# 조절: RV_ROUNDS(기본 3) RV_DURATION(30) RV_COOLDOWN(180) RV_EXT_ARMS("extauth extproc")
set -uo pipefail

PY="$1"; OUT_REL="$2"
CTX="aaif-benchmark"; NS="mcp-pilot"; AGWNS="agentgateway-system"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
MCPSTUDY="$(cd "$STUDY/../mcp-migration/studies/stateless-scaleout" && pwd)"
LOADGEN="$MCPSTUDY/harness/loadgen.py"
ROUNDS="${RV_ROUNDS:-3}"; DUR="${RV_DURATION:-30}"; COOLDOWN="${RV_COOLDOWN:-180}"
ARMS="${RV_EXT_ARMS:-extauth extproc}"
BIN="$STUDY/k8s/extproc/extproc-linux-arm64"
OUT="$STUDY/$OUT_REL"; mkdir -p "$OUT"
log() { echo "[ext $(date '+%m-%d %H:%M')] $*"; }
note() { echo "$*" >> "$OUT/FINDINGS.md"; }

GW=$(kubectl --context $CTX -n $AGWNS get gateway agentgateway-proxy -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
[ -z "$GW" ] && { log "[중단] 게이트웨이 주소 없음"; exit 1; }
AGWV=$(kubectl --context $CTX -n $AGWNS get deploy agentgateway-proxy -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | sed 's/.*://')

echo "# extAuth / extProc 인자 통제와 비용 (자동 생성, agentgateway $AGWV)" > "$OUT/FINDINGS.md"
note ""
note "실행 $(date '+%Y-%m-%d %H:%M'). 규칙은 결과 7과 같다: tools/call get-sum은 a == 1일 때만 허용."
note "검사 서버는 두 팔 모두 내내 상주하고 정책만 켰다 껐다 한다(자원 조건 통제)."
note "부하 ${ROUNDS}회 x ${DUR}초, 셀 간 쿨다운 ${COOLDOWN}초. 팔: $ARMS"
note ""

call() { # call <tag> <tool> <args-json>
  local tag="$1" tool="$2" args="$3"
  local code
  code=$(curl -s --max-time 8 -o "$OUT/$tag.json" -w "%{http_code}" -X POST "http://$GW/b" \
    -H 'Accept: application/json, text/event-stream' -H 'Content-Type: application/json' \
    -H 'MCP-Protocol-Version: 2026-07-28' -H 'Mcp-Method: tools/call' -H "Mcp-Name: $tool" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"$tool\",\"arguments\":$args,\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\",\"io.modelcontextprotocol/clientInfo\":{\"name\":\"rvext\",\"version\":\"0.1\"},\"io.modelcontextprotocol/clientCapabilities\":{}}}}")
  echo "HTTP $code $(head -c 140 "$OUT/$tag.json" | tr '\n' ' ')"
}
list_tools() { # list_tools <tag>
  local code
  code=$(curl -s --max-time 8 -o "$OUT/$1.json" -w "%{http_code}" -X POST "http://$GW/b" \
    -H 'Accept: application/json, text/event-stream' -H 'Content-Type: application/json' \
    -H 'MCP-Protocol-Version: 2026-07-28' -H 'Mcp-Method: tools/list' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"rvext","version":"0.1"},"io.modelcontextprotocol/clientCapabilities":{}}}}')
  echo "HTTP $code tools=$(grep -o '"name":' "$OUT/$1.json" | wc -l | tr -d ' ')"
}
probe_round() { # probe_round <prefix>
  local p="$1"
  note "- $p get-sum a=1 (통과 기대): \`$(call "$p-a1" get-sum '{"a":1,"b":2}')\`"
  note "- $p get-sum a=2 (거부 기대): \`$(call "$p-a2" get-sum '{"a":2,"b":2}')\`"
  note "- $p echo (통과 기대): \`$(call "$p-echo" echo '{"message":"x"}')\`"
  note "- $p tools/list: \`$(list_tools "$p-list")\`"
}
cell() { # cell <name> <mode>
  "$PY" "$LOADGEN" --url "http://$GW/b" --dialect b --tool echo \
    --concurrency 8 --duration "$DUR" --conn-mode "$2" --rps 100 \
    --out "$OUT/$1.json" >/dev/null 2>&1
  "$PY" -c "
import json
d=json.load(open('$OUT/$1.json'))
err=sum(d.get('errors', {}).values())
print(f\"achieved={d['achieved_rps']:.1f} p50={d['latency_ms']['p50']:.1f} p99={d['latency_ms']['p99']:.1f} err={err}\")"
}
del_policy() { kubectl --context $CTX -n $NS delete agentgatewaypolicy rv-ext >/dev/null 2>&1; sleep 8; }
pstatus() { kubectl --context $CTX -n $NS get agentgatewaypolicy rv-ext -o jsonpath='Accepted={.status.ancestors[0].conditions[?(@.type=="Accepted")].status}({.status.ancestors[0].conditions[?(@.type=="Accepted")].reason}) Attached={.status.ancestors[0].conditions[?(@.type=="Attached")].status}' 2>/dev/null; }

apply_extauth() {
  cat <<YAML | kubectl --context $CTX apply -f - >> "$OUT/apply.log" 2>&1
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata:
  name: rv-ext
  namespace: mcp-pilot
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: mcp-b
  traffic:
    extAuth:
      backendRef:
        kind: Service
        name: extauth
        namespace: mcp-pilot
        port: 8000
      failureMode: FailClosed
      http:
        path: '"/check"'   # CEL 표현식이라 문자열 리터럴로 감싼다
        body: '{"body": string(request.body)}'
YAML
  sleep 12
}
apply_extproc() {
  cat <<YAML | kubectl --context $CTX apply -f - >> "$OUT/apply.log" 2>&1
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata:
  name: rv-ext
  namespace: mcp-pilot
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: mcp-b
  traffic:
    extProc:
      backendRef:
        kind: Service
        name: extproc
        namespace: mcp-pilot
        port: 18080
      failureMode: FailClosed
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
  log "정리 완료(검사 서버 2종, 정책 제거)"
}
trap cleanup EXIT

run_arm() { # run_arm <extauth|extproc>
  local arm="$1"
  note "## ${arm} 팔"
  note ""
  if [ "$arm" = extauth ]; then
    log "extAuth 서버 배포"
    kubectl --context $CTX -n $NS delete configmap extauth-code >/dev/null 2>&1
    kubectl --context $CTX -n $NS create configmap extauth-code --from-file="$STUDY/k8s/extauth/server.py" >> "$OUT/apply.log" 2>&1
    kubectl --context $CTX apply -f "$STUDY/k8s/extauth/extauth.yaml" >> "$OUT/apply.log" 2>&1
    kubectl --context $CTX -n $NS rollout status deploy/extauth --timeout=300s >> "$OUT/apply.log" 2>&1 \
      || { note "**중단**: extauth 기동 실패"; return 1; }
  else
    [ -x "$BIN" ] || { note "**건너뜀**: $BIN 없음(빌드 필요)"; return 0; }
    log "extProc 서버 배포"
    kubectl --context $CTX apply -f "$STUDY/k8s/extproc/extproc.yaml" >> "$OUT/apply.log" 2>&1
    sleep 10
    local pod
    pod=$(kubectl --context $CTX -n $NS get pod -l app=extproc -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    [ -z "$pod" ] && { note "**중단**: extproc 파드 없음"; return 1; }
    kubectl --context $CTX -n $NS wait --for=condition=Ready "pod/$pod" --timeout=180s >> "$OUT/apply.log" 2>&1
    kubectl --context $CTX -n $NS cp "$BIN" "$pod:/work/extproc" >> "$OUT/apply.log" 2>&1 \
      || { note "**중단**: 바이너리 복사 실패"; return 1; }
    sleep 15
  fi
  sleep 5
  note "### 정책 없음 기준선"
  probe_round "$arm-base"
  note ""
  log "$arm 정책 적용"
  if [ "$arm" = extauth ]; then apply_extauth; else apply_extproc; fi
  note "### 정책 적용 (상태: \`$(pstatus)\`)"
  probe_round "$arm-on"
  note ""
  note "검사 서버 로그(마지막 12줄):"
  note '```'
  kubectl --context $CTX -n $NS logs "deploy/$arm" --tail=12 >> "$OUT/FINDINGS.md" 2>&1
  note '```'
  note ""
  note "### 비용 (정책 끔 대 켬, 100rps)"
  note ""
  for mode in close reuse; do
    note "**$mode 모드**"
    note ""
    for n in $(seq 1 "$ROUNDS"); do
      del_policy
      note "- off n$n: $(cell "$arm-off-$mode-n$n" "$mode")"
      sleep "$COOLDOWN"
      if [ "$arm" = extauth ]; then apply_extauth; else apply_extproc; fi
      note "- on  n$n: $(cell "$arm-on-$mode-n$n" "$mode")"
      sleep "$COOLDOWN"
    done
    note ""
  done
  del_policy
  note "- (원복 확인) get-sum a=2: \`$(call "$arm-clean" get-sum '{"a":2,"b":2}')\`"
  note ""
}

for arm in $ARMS; do run_arm "$arm"; done
note "---"
note "판정 기준: a=1 통과 + a=2 거부면 그 경로로 인자 통제가 된다. 비용은 결과 7의"
note "guardrail 증분(호출당 p50 +0.1~0.7ms)과 견준다."
log "=== rv_ext 완료: $OUT ==="
