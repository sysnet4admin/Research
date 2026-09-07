#!/usr/bin/env bash
# PR #3301(main, 2026-09-03 병합, 미릴리스)이 #3092에 미치는 영향 실측.
# reverify_authz.sh(v1.5.0 P2 재현)의 최소 델타 사본. aaif-benchmark 전용.
# 시퀀스: 통제 -> v1.5.0 + 라우트 authorization(인자 조건) -> 프록시 이미지를
# dev(v0.0.0-alpha.748b38b2, #3301 포함)로 교체 -> 라우트 authorization 재프로브
# -> mcpAuthorization 인자 조건(P2 원형) 재프로브 -> 이미지 원복 + 통제.
# 사용: ./rv_3301.sh runs/pr3301-0907
set -uo pipefail

BASE="$1"; CTX="aaif-benchmark"; NS="mcp-pilot"; GW="http://192.168.2.102"
DEV_IMG="ghcr.io/agentgateway/agentgateway:v0.0.0-alpha.748b38b2"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
mkdir -p "$STUDY/$BASE"; OUT="$STUDY/$BASE"
note() { echo "$*" >> "$OUT/FINDINGS.md"; }
img() { kubectl --context $CTX -n agentgateway-system get deploy agentgateway-proxy -o jsonpath='{.spec.template.spec.containers[0].image}'; }
ORIG_IMG="$(img)"

call() { # call <tag> <tool> <json-args>
  local tag="$1" tool="$2" args="$3"
  curl -s --max-time 8 -o "$OUT/$tag.json" -w "%{http_code}" -X POST "$GW/b" \
    -H 'Accept: application/json, text/event-stream' -H 'Content-Type: application/json' \
    -H 'MCP-Protocol-Version: 2026-07-28' -H 'Mcp-Method: tools/call' -H "Mcp-Name: $tool" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"$tool\",\"arguments\":$args,\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\",\"io.modelcontextprotocol/clientInfo\":{\"name\":\"rv3301\",\"version\":\"0.1\"},\"io.modelcontextprotocol/clientCapabilities\":{}}}}"
}
list_tools() { # list_tools <tag>
  curl -s --max-time 8 -o "$OUT/$1.json" -w "%{http_code}" -X POST "$GW/b" \
    -H 'Accept: application/json, text/event-stream' -H 'Content-Type: application/json' \
    -H 'MCP-Protocol-Version: 2026-07-28' -H 'Mcp-Method: tools/list' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"rv3301","version":"0.1"},"io.modelcontextprotocol/clientCapabilities":{}}}}'
}
probe_round() { # probe_round <prefix>
  local p="$1"
  note "- $p get-sum a=1: HTTP $(call "$p-a1" get-sum '{"a":1,"b":2}') $(head -c 120 "$OUT/$p-a1.json" | tr '\n' ' ')"
  note "- $p get-sum a=2: HTTP $(call "$p-a2" get-sum '{"a":2,"b":2}') $(head -c 120 "$OUT/$p-a2.json" | tr '\n' ' ')"
  note "- $p echo: HTTP $(call "$p-echo" echo '{"message":"x"}') $(head -c 120 "$OUT/$p-echo.json" | tr '\n' ' ')"
  note "- $p tools/list: HTTP $(list_tools "$p-list") tools=$(grep -o '"name":' "$OUT/$p-list.json" | wc -l | tr -d ' ') $(head -c 100 "$OUT/$p-list.json" | tr '\n' ' ')"
}
apply_backend_policy() { # mcpAuthorization (P2 원형)
  cat <<YAML | kubectl --context $CTX apply -f - >/dev/null
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata:
  name: rv-3301-backend
  namespace: mcp-pilot
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
            - '$1'
YAML
  sleep 12
}
apply_route_policy() { # apply_route_policy <action> <expr>  (traffic.authorization, HTTPRoute mcp-b)
  cat <<YAML | kubectl --context $CTX apply -f - >/dev/null
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata:
  name: rv-3301-route
  namespace: mcp-pilot
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: mcp-b
  traffic:
    authorization:
      action: $1
      policy:
        matchExpressions:
          - '$2'
YAML
  sleep 12
}
pstatus() { kubectl --context $CTX -n $NS get agentgatewaypolicy "$1" -o jsonpath='Accepted={.status.ancestors[0].conditions[?(@.type=="Accepted")].status}({.status.ancestors[0].conditions[?(@.type=="Accepted")].reason}) Attached={.status.ancestors[0].conditions[?(@.type=="Attached")].status}' 2>/dev/null; }
cleanup_policies() { kubectl --context $CTX -n $NS delete agentgatewaypolicy rv-3301-route rv-3301-backend >/dev/null 2>&1; sleep 8; }
# 프록시 Deployment는 컨트롤러가 Gateway에서 생성하므로 kubectl set image는 즉시 되돌려진다
# (1차 실행 14:24에서 확인). helm 값(proxy.image.*)으로 바꾼다.
CHART="oci://cr.agentgateway.dev/charts/agentgateway"; CHART_VER="v1.5.0"
wait_image() { # wait_image <expected-image>
  for i in $(seq 1 60); do [ "$(img)" = "$1" ] && break; sleep 5; done
  [ "$(img)" = "$1" ] || return 1
  kubectl --context $CTX -n agentgateway-system rollout status deploy/agentgateway-proxy --timeout=300s >/dev/null 2>&1 || return 1
  sleep 5
}
set_dev_image() {
  helm --kube-context $CTX -n agentgateway-system upgrade agentgateway $CHART --version $CHART_VER \
    --reuse-values --set proxy.image.registry=ghcr.io/agentgateway --set proxy.image.tag=v0.0.0-alpha.748b38b2 --wait >/dev/null 2>&1 || return 1
  wait_image "$DEV_IMG"
}
restore() {
  cleanup_policies
  helm --kube-context $CTX -n agentgateway-system upgrade agentgateway $CHART --version $CHART_VER --reset-values --wait >/dev/null 2>&1
  wait_image "$ORIG_IMG"; note "- 원복 후 이미지: $(img)"
}
trap 'restore' EXIT

DENY_EXPR='mcp.tool.name == "get-sum" && mcp.tool.arguments.a != 1'
ALLOW_EXPR='!has(mcp.tool) || mcp.tool.name != "get-sum" || mcp.tool.arguments.a == 1'
P2_EXPR='mcp.tool.name == "get-sum" && mcp.tool.arguments.a == 1'

echo "# PR #3301 영향 실측 (자동 생성, aaif-benchmark, K8s 1.37.0)" > "$OUT/FINDINGS.md"
note ""
note "시작 $(date '+%Y-%m-%d %H:%M'). 원본 이미지 $ORIG_IMG, dev 이미지 $DEV_IMG"
note ""
note "## 0. 통제 (v1.5.0, 정책 없음)"
probe_round c0
note ""
note "## 1. v1.5.0 + 라우트 traffic.authorization Deny: $DENY_EXPR"
apply_route_policy Deny "$DENY_EXPR"; note "- 정책 상태: $(pstatus rv-3301-route)"; probe_round v150-deny
note ""
note "## 2. v1.5.0 + 라우트 traffic.authorization Allow: $ALLOW_EXPR"
apply_route_policy Allow "$ALLOW_EXPR"; note "- 정책 상태: $(pstatus rv-3301-route)"; probe_round v150-allow
cleanup_policies
note ""
note "## 3. 프록시 이미지 교체 -> dev ($DEV_IMG)"
if set_dev_image; then note "- 롤아웃 완료. 이미지: $(img). 컨트롤러는 v1.5.0 유지"; else note "- 롤아웃 실패 (원복)"; exit 1; fi
note "- dev 통제 (정책 없음)"; probe_round dev-c0
note ""
note "## 4. dev + 라우트 traffic.authorization Deny: $DENY_EXPR"
apply_route_policy Deny "$DENY_EXPR"; note "- 정책 상태: $(pstatus rv-3301-route)"; probe_round dev-deny
note ""
note "## 5. dev + 라우트 traffic.authorization Allow: $ALLOW_EXPR"
apply_route_policy Allow "$ALLOW_EXPR"; note "- 정책 상태: $(pstatus rv-3301-route)"; probe_round dev-allow
cleanup_policies
note ""
note "## 6. dev + mcpAuthorization 인자 조건 (P2 원형): $P2_EXPR"
apply_backend_policy "$P2_EXPR"; note "- 정책 상태: $(pstatus rv-3301-backend)"; probe_round dev-p2
cleanup_policies
note ""
note "## 7. 원복 (v1.5.0)"
trap - EXIT
restore
probe_round restored
note ""
note "종료 $(date '+%Y-%m-%d %H:%M')"
echo "=== rv_3301 완료 ==="
