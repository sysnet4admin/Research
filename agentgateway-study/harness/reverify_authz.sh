#!/usr/bin/env bash
# v1.5.0 인가 재확인 (#3092 재현 실측). aaif-benchmark 클러스터 전용.
# 시퀀스: 통제(정책 없음) -> 인자 조건 정책 -> has() 가드 정책 -> 정리.
# 사용: ./reverify_authz.sh runs/reverify-0831
set -uo pipefail

BASE="$1"; CTX="aaif-benchmark"; NS="mcp-pilot"; GW="http://192.168.2.102"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
mkdir -p "$STUDY/$BASE"; OUT="$STUDY/$BASE"
note() { echo "$*" >> "$OUT/FINDINGS.md"; }

call() { # call <tag> <tool> <json-args>
  local tag="$1" tool="$2" args="$3"
  curl -s --max-time 8 -o "$OUT/$tag.json" -w "%{http_code}" -X POST "$GW/b" \
    -H 'Accept: application/json, text/event-stream' -H 'Content-Type: application/json' \
    -H 'MCP-Protocol-Version: 2026-07-28' -H 'Mcp-Method: tools/call' -H "Mcp-Name: $tool" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"$tool\",\"arguments\":$args,\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\",\"io.modelcontextprotocol/clientInfo\":{\"name\":\"reverify\",\"version\":\"0.1\"},\"io.modelcontextprotocol/clientCapabilities\":{}}}}"
}
list_tools() { # list_tools <tag>
  curl -s --max-time 8 -o "$OUT/$1.json" -w "%{http_code}" -X POST "$GW/b" \
    -H 'Accept: application/json, text/event-stream' -H 'Content-Type: application/json' \
    -H 'MCP-Protocol-Version: 2026-07-28' -H 'Mcp-Method: tools/list' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"reverify","version":"0.1"},"io.modelcontextprotocol/clientCapabilities":{}}}}'
}
probe_round() { # probe_round <prefix>
  local p="$1"
  note "- $p get-sum a=1: HTTP $(call "$p-a1" get-sum '{"a":1,"b":2}') $(head -c 120 "$OUT/$p-a1.json" | tr '\n' ' ')"
  note "- $p get-sum a=2: HTTP $(call "$p-a2" get-sum '{"a":2,"b":2}') $(head -c 120 "$OUT/$p-a2.json" | tr '\n' ' ')"
  note "- $p echo: HTTP $(call "$p-echo" echo '{"message":"x"}') $(head -c 120 "$OUT/$p-echo.json" | tr '\n' ' ')"
  note "- $p tools/list: HTTP $(list_tools "$p-list") $(head -c 200 "$OUT/$p-list.json" | tr '\n' ' ')"
}
apply_policy() { # apply_policy <expr>
  cat <<YAML | kubectl --context $CTX apply -f - >/dev/null
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata:
  name: rv-authz
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
            - $1
YAML
  sleep 12
}

echo "# v1.5.0 인가 재확인 (자동 생성, aaif-benchmark, agw v1.5.0, K8s 1.37.0)" > "$OUT/FINDINGS.md"
note ""
note "시작 $(date '+%Y-%m-%d %H:%M')"
note ""
note "## 0. 통제 (정책 없음)"
probe_round c0
note ""
note "## 1. 인자 조건 정책 (mcp.tool.name == get-sum && mcp.tool.arguments.a == 1)"
apply_policy 'mcp.tool.name == "get-sum" && mcp.tool.arguments.a == 1'
note "- 정책 상태: $(kubectl --context $CTX -n $NS get agentgatewaypolicy rv-authz -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}{" "}{.status.conditions[?(@.type=="Accepted")].reason}' 2>/dev/null)"
probe_round p1
note ""
note "## 2. has() 가드 정책 (!has(...) || a == 1)"
apply_policy 'mcp.tool.name == "get-sum" && (!has(mcp.tool.arguments) || mcp.tool.arguments.a == 1)'
note "- 정책 상태: $(kubectl --context $CTX -n $NS get agentgatewaypolicy rv-authz -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null)"
probe_round p2
note ""
note "## 정리"
kubectl --context $CTX -n $NS delete agentgatewaypolicy rv-authz >/dev/null 2>&1
sleep 8
note "- 정책 제거 후 echo: HTTP $(call clean-echo echo '{"message":"x"}') $(head -c 80 "$OUT/clean-echo.json" | tr '\n' ' ')"
note ""
note "종료 $(date '+%Y-%m-%d %H:%M')"
echo "=== reverify_authz 완료 ==="