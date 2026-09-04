#!/usr/bin/env bash
# [rv 사본] t1p3_addendum.sh의 P3 보강부만. v1.5.0 + aaif-benchmark 상주 환경용
# (설치/제거 없음, CTX 교체). T1은 rv_run_axes.sh가 이미 탭으로 재측정했으므로 제외.
# 사용: ./rv_p3sup.sh <PYTHON> <OUT_DIR>
set -uo pipefail

PY="$1"; OUT="$2"
CTX="aaif-benchmark"; NS="mcp-pilot"
mkdir -p "$OUT"

log() { echo "[$(date '+%m-%d %H:%M')] $*"; }
note() { echo "$*" >> "$OUT/FINDINGS.md"; }

kubectl --context $CTX -n $NS get agentgatewaybackend mcp-b-stateless >/dev/null 2>&1 \
  || { log "[중단] 백엔드 mcp-b-stateless 없음"; exit 1; }
GW=$(kubectl --context $CTX -n agentgateway-system get gateway agentgateway-proxy -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
[ -z "$GW" ] && { log "[중단] 게이트웨이 주소 없음"; exit 1; }
GW="http://$GW"
log "게이트웨이 주소: $GW (상주 환경 재사용)"
kubectl --context $CTX -n $NS get agentgatewaypolicy -o name 2>/dev/null | grep -q . && { log "[중단] 잔여 정책 있음"; exit 1; }

call() { # call <path> <tool>
  "$PY" - "$GW" "$1" "$2" <<'PYEOF'
import json, sys, httpx
gw, path, tool = sys.argv[1], sys.argv[2], sys.argv[3]
h = {"Accept": "application/json, text/event-stream", "Content-Type": "application/json",
     "MCP-Protocol-Version": "2026-07-28", "Mcp-Method": "tools/call", "Mcp-Name": tool}
args = {"message": "ping"} if tool.endswith("echo") else ({"a": 1, "b": 2} if "sum" in tool else {})
body = {"jsonrpc": "2.0", "id": 1, "method": "tools/call",
        "params": {"name": tool, "arguments": args,
                   "_meta": {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
                             "io.modelcontextprotocol/clientInfo": {"name": "axes", "version": "0.1"},
                             "io.modelcontextprotocol/clientCapabilities": {}}}}
try:
    r = httpx.post(f"{gw}{path}", headers=h, json=body, timeout=20)
    txt = r.text[:220].replace("\n", " ")
    print(json.dumps({"status": r.status_code, "body": txt}, ensure_ascii=False))
except Exception as e:
    print(json.dumps({"status": 0, "body": f"{type(e).__name__}: {e}"}, ensure_ascii=False))
PYEOF
}

apply_policy() {
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
$2
YAML
  sleep 12
}
drop_policy() { kubectl --context $CTX -n $NS delete agentgatewaypolicy "$1" >/dev/null 2>&1; sleep 8; }
set_prefix() {
  kubectl --context $CTX -n $NS patch agentgatewaybackend mcp-b-stateless --type merge \
    -p "{\"spec\":{\"mcp\":{\"prefixMode\":\"$1\"}}}" >/dev/null 2>&1
  sleep 12
}

echo "# P3 보강 재측정: Always 모드 실제 재작명 이름 (자동 생성, v1.5.0)" > "$OUT/FINDINGS.md"
note ""
note "실행 $(date '+%Y-%m-%d %H:%M'). 컨텍스트 $CTX, agentgateway $(kubectl --context $CTX -n agentgateway-system get deploy agentgateway-proxy -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | sed 's/.*://'). t1p3-0818(v1.4.1)의 P3 보강과 같은 프로브."
note ""
log "P3 보강: Always 모드 실제 접두사(mcp-b-80_)"
note "## P3 보강. Always 모드, 실제 재작명 이름"
note ""
set_prefix Always
note "- 정책 없음"
note "  - mcp-b-80_echo 호출(양성 대조): \`$(call /b mcp-b-80_echo)\`"
note "  - mcp-b-80_get-sum 호출: \`$(call /b mcp-b-80_get-sum)\`"
apply_policy ax-p3a '            - mcp.tool.name == "echo"'
note "- 정책 = 원명 \`echo\` 허용"
note "  - mcp-b-80_echo 호출(정책이 원명을 보면 허용 기대): \`$(call /b mcp-b-80_echo)\`"
note "  - mcp-b-80_get-sum 호출(우회 시험, 차단 기대): \`$(call /b mcp-b-80_get-sum)\`"
drop_policy ax-p3a
apply_policy ax-p3b '            - mcp.tool.name == "mcp-b-80_echo"'
note "- 정책 = 재작명명 \`mcp-b-80_echo\` 허용"
note "  - mcp-b-80_echo 호출: \`$(call /b mcp-b-80_echo)\`"
note "  - echo 호출: \`$(call /b echo)\`"
note "  - mcp-b-80_get-sum 호출: \`$(call /b mcp-b-80_get-sum)\`"
drop_policy ax-p3b
set_prefix Conditional
note "  - (원복 확인) Conditional에서 echo 호출: \`$(call /b echo)\`"
note ""
note "판정 기준: 원명 정책 아래 mcp-b-80_get-sum이 통과하면 재작명 우회가 실재한다."
note "mcp-b-80_echo가 어느 정책에서 통과하는지가 정책이 보는 이름을 확정한다."
log "=== 보강 완료: $OUT ==="
