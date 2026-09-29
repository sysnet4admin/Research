#!/usr/bin/env bash
# 실제 도구와 실제 클라이언트 보강 측정(2026-09-28, aaif-benchmark 클러스터). rv_3301.sh 의 정책 적용 방식과
# 판정 형식을 따르고 백엔드를 실제 쿠버네티스 MCP 서버(kmcp)로 바꾼 사본이다.
#
#   PHASE=A  v1.5.0 그대로. 측정 1 의 mcpAuthorization 셀, HTTP 계층 대조(수용되고 무효 예상),
#            Agent Router 셀, 측정 2 의 SDK 거부 반응(Unknown tool, Agent Router 403).
#   PHASE=B  agentgateway 를 v1.6.0-alpha.2(프리릴리스) 태그 차트로 올린 뒤 측정 3(get-sum 셀 재측정),
#            측정 1 의 HTTP 계층 셀, mcpAuthorization 셀 재확인, 측정 2 의 HTTP 계층 403.
#            복원은 이 스크립트가 하지 않는다. 판독 뒤 VM 스냅샷 pre-0928 로 되돌린다.
#
# 사용: PHASE=A ROUNDS=5 ./cfp_0928.sh runs/cfp-a-0928
set -uo pipefail
OUT_REL="$1"; PHASE="${PHASE:?PHASE=A|B}"; ROUNDS="${ROUNDS:-5}"
CTX="aaif-benchmark"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; STUDY="$(cd "$DIR/.." && pwd)"
OUT="$STUDY/$OUT_REL"; mkdir -p "$OUT"
PY="$HOME/.venvs/mcpbench/bin/python"; SDKPY="$HOME/.venvs/mcpsdk/bin/python"
PROBE="$DIR/kmcp_probe.py"; SDK="$DIR/sdk_reject_probe.py"
k() { kubectl --context $CTX "$@"; }
# 게이트웨이 주소는 스크립트에 적지 않고 클러스터의 LoadBalancer Service 에서 읽는다.
lb_ip() { k -n "$1" get svc "$2" -o jsonpath='{.status.loadBalancer.ingress[0].ip}'; }
AR_SVC="$(k -n envoy-gateway-system get svc -l gateway.envoyproxy.io/owning-gateway-name=ar-gw -o jsonpath='{.items[0].metadata.name}')"
export AGW_URL="http://$(lb_ip agentgateway-system agentgateway-proxy)"
export AR_URL="http://$(lb_ip envoy-gateway-system "$AR_SVC")"
export KCTX="$CTX"
note() { echo "$*" | tee -a "$OUT/FINDINGS.md"; }
agw_img() { k -n agentgateway-system get deploy agentgateway-proxy -o jsonpath='{.spec.template.spec.containers[0].image}'; }
agw_ctl() { k -n agentgateway-system get deploy agentgateway -o jsonpath='{.spec.template.spec.containers[0].image}'; }
pstatus() { k -n $NS get agentgatewaypolicy "$1" -o jsonpath='Accepted={.status.ancestors[0].conditions[?(@.type=="Accepted")].status}({.status.ancestors[0].conditions[?(@.type=="Accepted")].reason}) Attached={.status.ancestors[0].conditions[?(@.type=="Attached")].status}' 2>/dev/null; }
arstatus() { k -n $NS get mcproute ar-kmcp -o jsonpath='{range .status.conditions[*]}{.type}={.status}({.reason}) {end}' 2>/dev/null; }
cleanup() {
  k -n $NS delete agentgatewaypolicy cfp-backend cfp-route --ignore-not-found >/dev/null 2>&1
  k apply -f "$STUDY/k8s/kmcp/routes.yaml" >/dev/null 2>&1   # ar-kmcp 를 정책 없는 상태로
  k -n dev delete pod -l kmcp-probe=1 --ignore-not-found --wait=false >/dev/null 2>&1
  k -n prod delete pod -l kmcp-probe=1 --ignore-not-found --wait=false >/dev/null 2>&1
  sleep 12
}
done_mark() { touch "$OUT/.done-$1"; }
is_done() { [ -f "$OUT/.done-$1" ]; }

backend_policy() { # backend_policy <expr1> [<expr2>]
  local exprs=""
  for e in "$@"; do exprs="$exprs
            - '$e'"; done
  cat <<YAML | k apply -f - >/dev/null
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata: { name: cfp-backend, namespace: $NS }
spec:
  targetRefs: [{ group: agentgateway.dev, kind: AgentgatewayBackend, name: kmcp }]
  backend:
    mcp:
      authorization:
        policy:
          matchExpressions:$exprs
YAML
  sleep 12
}
route_policy() { # route_policy <HTTPRoute> <action> <expr>
  cat <<YAML | k apply -f - >/dev/null
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata: { name: cfp-route, namespace: $NS }
spec:
  targetRefs: [{ group: gateway.networking.k8s.io, kind: HTTPRoute, name: $1 }]
  traffic:
    authorization:
      action: $2
      policy:
        matchExpressions:
          - '$3'
YAML
  sleep 12
}
ar_policy() { # ar_policy <cel for pods_delete>
  cat <<YAML | k apply -f - >/dev/null
apiVersion: aigateway.envoyproxy.io/v1beta1
kind: MCPRoute
metadata: { name: ar-kmcp, namespace: $NS }
spec:
  parentRefs: [{ name: ar-gw, kind: Gateway, group: gateway.networking.k8s.io }]
  path: /kmcp
  backendRefs: [{ name: kmcp, kind: Backend, group: gateway.envoyproxy.io, path: /mcp }]
  securityPolicy:
    authorization:
      rules:
        - action: Allow
          target: { tools: [{ backend: kmcp, tool: pods_delete }] }
          cel: '$1'
        - action: Allow
          target: { tools: [{ backend: kmcp, tool: pods_list_in_namespace }] }
YAML
  sleep 15
}
rounds() { # rounds <gw> <cell>
  for r in $(seq 1 "$ROUNDS"); do
    $PY "$PROBE" --gw "$1" --cell "$2" --round "$r" --out "$OUT/cells" 2>&1 | tail -1 | tee -a "$OUT/FINDINGS.md"
  done
}
sdk() { # sdk <label> <url> <denied> <denied-args> <allowed> <allowed-args>
  for r in $(seq 1 "$(( ROUNDS < 3 ? ROUNDS : 3 ))"); do
    k -n prod run "sdk-$1-$r" --image=registry.k8s.io/pause:3.10 --restart=Never --labels=kmcp-probe=1 >/dev/null 2>&1
    k -n prod wait --for=condition=Ready "pod/sdk-$1-$r" --timeout=90s >/dev/null 2>&1
    local args="${4//__POD__/sdk-$1-$r}"
    mkdir -p "$OUT/sdk"
    $SDKPY "$SDK" --url "$2" --denied "$3" --denied-args "$args" --allowed "$5" --allowed-args "$6" \
      --label "$1-r$r" --out "$OUT/sdk/$1-r$r.json" 2>&1 | tail -1 | tee -a "$OUT/FINDINGS.md"
    note "  (파드 sdk-$1-$r 삭제 여부: $(k -n prod get pod "sdk-$1-$r" -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null || echo 없음))"
  done
}

DEL_DEV='mcp.tool.name == "pods_delete" && mcp.tool.arguments.namespace == "dev"'
DEL_DEV_GUARD='mcp.tool.name == "pods_delete" && (!has(mcp.tool.arguments) || mcp.tool.arguments.namespace == "dev")'
LIST_OK='mcp.tool.name == "pods_list_in_namespace"'
H_DENY='mcp.tool.name == "pods_delete" && mcp.tool.arguments.namespace != "dev"'
H_ALLOW='!has(mcp.tool) || mcp.tool.name != "pods_delete" || mcp.tool.arguments.namespace == "dev"'
AR_DOC='request.mcp.params.arguments.namespace == "dev"'
AR_GUARD='!has(request.mcp.params.arguments) || request.mcp.params.arguments.namespace == "dev"'
KMCP_IMG="$(k -n $NS get deploy kmcp -o jsonpath='{.spec.template.spec.containers[0].image}')"

agw_cells() { # agw_cells <접두어>  mcpAuthorization 두 셀 + HTTP 계층 두 셀
  local p="$1"
  if ! is_done "$p-g1"; then
    note ""; note "### $p G1 mcpAuthorization 인자 규칙 그대로: [$LIST_OK] OR [$DEL_DEV]"
    backend_policy "$LIST_OK" "$DEL_DEV"; note "- 정책 상태: $(pstatus cfp-backend)"
    rounds agw "$p-g1"; cleanup; done_mark "$p-g1"
  fi
  if ! is_done "$p-g2"; then
    note ""; note "### $p G2 mcpAuthorization + has() 가드: [$LIST_OK] OR [$DEL_DEV_GUARD]"
    backend_policy "$LIST_OK" "$DEL_DEV_GUARD"; note "- 정책 상태: $(pstatus cfp-backend)"
    rounds agw "$p-g2"; cleanup; done_mark "$p-g2"
  fi
  if ! is_done "$p-hd"; then
    note ""; note "### $p H-deny HTTP 계층 authorization Deny: $H_DENY"
    route_policy kmcp Deny "$H_DENY"; note "- 정책 상태: $(pstatus cfp-route)"
    rounds agw "$p-hd"; cleanup; done_mark "$p-hd"
  fi
  if ! is_done "$p-ha"; then
    note ""; note "### $p H-allow HTTP 계층 authorization Allow: $H_ALLOW"
    route_policy kmcp Allow "$H_ALLOW"; note "- 정책 상태: $(pstatus cfp-route)"
    rounds agw "$p-ha"; cleanup; done_mark "$p-ha"
  fi
}

[ -f "$OUT/FINDINGS.md" ] || {
  echo "# 실제 도구와 실제 클라이언트 보강 측정 PHASE=$PHASE (자동 생성, aaif-benchmark, K8s 1.37.0)" > "$OUT/FINDINGS.md"
}
note ""; note "## 시작 $(date '+%Y-%m-%d %H:%M') ROUNDS=$ROUNDS"
note "- agentgateway 컨트롤러 $(agw_ctl), 프록시 $(agw_img)"
note "- 백엔드 $KMCP_IMG (SA kmcp: dev, prod 파드 조회와 삭제만)"
cleanup

if [ "$PHASE" = "A" ]; then
  if ! is_done a-c0; then
    note ""; note "### A 대조 (정책 없음)"
    rounds agw a-c0; rounds ar a-c0; done_mark a-c0
  fi
  agw_cells a
  if ! is_done a-r1; then
    note ""; note "### A R1 Agent Router 문서 예시 형태: pods_delete Allow cel [$AR_DOC], pods_list_in_namespace Allow"
    ar_policy "$AR_DOC"; note "- MCPRoute 상태: $(arstatus)"
    rounds ar a-r1; done_mark a-r1
    note ""; note "### A SDK: Agent Router 403 (R1 아래 prod 삭제)"
    sdk ar403 $AR_URL/kmcp kmcp__pods_delete '{"name":"__POD__","namespace":"prod"}' \
      kmcp__pods_list_in_namespace '{"namespace":"dev"}'
    cleanup
  fi
  if ! is_done a-r2; then
    note ""; note "### A R2 Agent Router !has() 가드: pods_delete Allow cel [$AR_GUARD], pods_list_in_namespace Allow"
    ar_policy "$AR_GUARD"; note "- MCPRoute 상태: $(arstatus)"
    rounds ar a-r2; cleanup; done_mark a-r2
  fi
  if ! is_done a-sdk-unknown; then
    note ""; note "### A SDK: agentgateway mcpAuthorization Unknown tool (G1 아래 prod 삭제)"
    backend_policy "$LIST_OK" "$DEL_DEV"
    sdk agwunknown $AGW_URL/k pods_delete '{"name":"__POD__","namespace":"prod"}' \
      pods_list_in_namespace '{"namespace":"dev"}'
    note ""; note "### A SDK: agentgateway mcpAuthorization + has() 가드 (G2 아래 prod 삭제, fail-open 이면 통과)"
    backend_policy "$LIST_OK" "$DEL_DEV_GUARD"
    sdk agwguard $AGW_URL/k pods_delete '{"name":"__POD__","namespace":"prod"}' \
      pods_list_in_namespace '{"namespace":"dev"}'
    cleanup; done_mark a-sdk-unknown
  fi
fi

if [ "$PHASE" = "B" ]; then
  AGW_NEW="v1.6.0-alpha.2"
  if ! is_done b-upgrade; then
    note ""; note "### B agentgateway -> $AGW_NEW (프리릴리스 태그 차트, CRD 와 컨트롤 플레인 모두)"
    helm --kube-context $CTX upgrade -i agentgateway-crds oci://cr.agentgateway.dev/charts/agentgateway-crds \
      --namespace agentgateway-system --version "$AGW_NEW" >>"$OUT/helm.log" 2>&1 || { note "- CRD 업그레이드 실패"; exit 1; }
    helm --kube-context $CTX upgrade agentgateway oci://cr.agentgateway.dev/charts/agentgateway \
      --namespace agentgateway-system --version "$AGW_NEW" --reset-values --wait >>"$OUT/helm.log" 2>&1 \
      || { note "- 컨트롤 플레인 업그레이드 실패"; exit 1; }
    for i in $(seq 1 60); do agw_img | grep -q "$AGW_NEW" && break; sleep 5; done
    k -n agentgateway-system rollout status deploy/agentgateway-proxy --timeout=300s >/dev/null 2>&1
    sleep 10
    note "- 업그레이드 후 컨트롤러 $(agw_ctl), 프록시 $(agw_img)"
    agw_img | grep -q "$AGW_NEW" || { note "- 프록시가 $AGW_NEW 가 아니다. 중단"; exit 1; }
    done_mark b-upgrade
  fi
  if ! is_done b-3301; then
    note ""; note "### B 측정 3: #3301 셀 재측정 (백엔드 mcp-b, get-sum). 9/7 dev 빌드와 같은 식"
    GW=$AGW_URL
    call() { curl -s --max-time 8 -o "$OUT/m3/$1.json" -w "%{http_code}" -X POST "$GW/b" \
      -H 'Accept: application/json, text/event-stream' -H 'Content-Type: application/json' \
      -H 'MCP-Protocol-Version: 2026-07-28' -H 'Mcp-Method: tools/call' -H "Mcp-Name: $2" \
      -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"$2\",\"arguments\":$3,\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\",\"io.modelcontextprotocol/clientInfo\":{\"name\":\"cfp0928\",\"version\":\"0.1\"},\"io.modelcontextprotocol/clientCapabilities\":{}}}}"; }
    list_tools() { curl -s --max-time 8 -o "$OUT/m3/$1.json" -w "%{http_code}" -X POST "$GW/b" \
      -H 'Accept: application/json, text/event-stream' -H 'Content-Type: application/json' \
      -H 'MCP-Protocol-Version: 2026-07-28' -H 'Mcp-Method: tools/list' \
      -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"cfp0928","version":"0.1"},"io.modelcontextprotocol/clientCapabilities":{}}}}'; }
    m3_round() { local p="$1"
      note "- $p get-sum a=1: HTTP $(call "$p-a1" get-sum '{"a":1,"b":2}') $(head -c 110 "$OUT/m3/$p-a1.json" | tr '\n' ' ')"
      note "- $p get-sum a=2: HTTP $(call "$p-a2" get-sum '{"a":2,"b":2}') $(head -c 110 "$OUT/m3/$p-a2.json" | tr '\n' ' ')"
      note "- $p echo: HTTP $(call "$p-echo" echo '{"message":"x"}') $(head -c 110 "$OUT/m3/$p-echo.json" | tr '\n' ' ')"
      note "- $p tools/list: HTTP $(list_tools "$p-list") tools=$(grep -o '"name":' "$OUT/m3/$p-list.json" | wc -l | tr -d ' ')"; }
    mkdir -p "$OUT/m3"
    for r in $(seq 1 "$ROUNDS"); do m3_round "c0-r$r"; done
    note "#### route Deny: mcp.tool.name == \"get-sum\" && mcp.tool.arguments.a != 1"
    route_policy mcp-b Deny 'mcp.tool.name == "get-sum" && mcp.tool.arguments.a != 1'; note "- 정책 상태: $(pstatus cfp-route)"
    for r in $(seq 1 "$ROUNDS"); do m3_round "deny-r$r"; done; cleanup
    note "#### route Allow: !has(mcp.tool) || mcp.tool.name != \"get-sum\" || mcp.tool.arguments.a == 1"
    route_policy mcp-b Allow '!has(mcp.tool) || mcp.tool.name != "get-sum" || mcp.tool.arguments.a == 1'; note "- 정책 상태: $(pstatus cfp-route)"
    for r in $(seq 1 "$ROUNDS"); do m3_round "allow-r$r"; done; cleanup
    done_mark b-3301
  fi
  agw_cells b
  if ! is_done b-sdk-403; then
    note ""; note "### B SDK: agentgateway HTTP 계층 403 (H-deny 아래 prod 삭제)"
    route_policy kmcp Deny "$H_DENY"
    sdk agw403 $AGW_URL/k pods_delete '{"name":"__POD__","namespace":"prod"}' \
      pods_list_in_namespace '{"namespace":"dev"}'
    cleanup; done_mark b-sdk-403
  fi
fi
note ""; note "## 종료 $(date '+%Y-%m-%d %H:%M')"
echo "=== cfp_0928 PHASE=$PHASE 완료 ==="
