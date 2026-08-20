#!/usr/bin/env bash
# 보강 측정 (2026-08-18). 두 가지를 고쳐 다시 잰다.
#   1. T1 traceparent: call()의 "${4:-{}}" bash 확장 버그(여분 } 부착)로 본측정과
#      스파이크 G5의 프로브가 전부 파이썬 크래시였다. 탭에 트래픽이 간 적이
#      없으므로 "전파 안 됨"은 허위 음성. 고쳐서 처음으로 유효 판정을 낸다.
#   2. P3 보강: Always 모드의 실제 접두사는 mcp-b_가 아니라 mcp-b-80_(서비스-포트)
#      였다. 실제 재작명 이름으로 양성 대조(mcp-b-80_echo)와 우회 시험
#      (mcp-b-80_get-sum)을 한다.
# 사용: ./t1p3_addendum.sh <PYTHON> <OUT_DIR>
set -uo pipefail

PY="$1"; OUT="$2"
CTX="mcp-migration"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCPSTUDY="$(cd "$DIR/../../mcp-migration/studies/stateless-scaleout" && pwd)"
GWDIR="$MCPSTUDY/k8s/agentgateway"
mkdir -p "$OUT"

log() { echo "[$(date '+%m-%d %H:%M')] $*"; }
note() { echo "$*" >> "$OUT/FINDINGS.md"; }

log "agentgateway v1.4.1 설치"
AGW_VER=v1.4.1 bash "$GWDIR/install.sh" > "$OUT/install.log" 2>&1
sleep 30
kubectl --context $CTX apply -f "$GWDIR/gateway.yaml" >> "$OUT/install.log" 2>&1
kubectl --context $CTX apply -f "$MCPSTUDY/k8s/tap-proxy.yaml" >> "$OUT/install.log" 2>&1
kubectl --context $CTX -n $NS rollout status deploy/tap-proxy --timeout=180s >> "$OUT/install.log" 2>&1
sleep 20
GW=$(kubectl --context $CTX -n agentgateway-system get gateway agentgateway-proxy -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
[ -z "$GW" ] && { log "[중단] 게이트웨이 주소 없음"; exit 1; }
GW="http://$GW"
log "게이트웨이 주소: $GW"

call() { # call <path> <tool> [args-json] [extra-header-json]
  local args_json="${3-}"; [ -z "$args_json" ] && args_json="null"
  local extra_json="${4-}"; [ -z "$extra_json" ] && extra_json="{}"
  "$PY" - "$GW" "$1" "$2" "$args_json" "$extra_json" <<'PYEOF'
import json, sys, httpx
gw, path, tool = sys.argv[1], sys.argv[2], sys.argv[3]
args_override, extra = json.loads(sys.argv[4]), json.loads(sys.argv[5])
h = {"Accept": "application/json, text/event-stream", "Content-Type": "application/json",
     "MCP-Protocol-Version": "2026-07-28", "Mcp-Method": "tools/call", "Mcp-Name": tool}
h.update(extra)
if args_override is not None:
    args = args_override
else:
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

echo "# 보강 측정: P3 실제 접두사 + T1 traceparent 유효 재측정 (자동 생성)" > "$OUT/FINDINGS.md"
note ""
note "실행 $(date '+%Y-%m-%d %H:%M'). 본측정 axes-0818의 두 결함을 고친 보강분이다."
note "T1은 call()의 bash 확장 버그로 프로브가 전부 크래시였고(허위 음성), P3 Always"
note "모드는 실제 접두사(mcp-b-80_)가 아닌 이름으로만 시험했었다."
note ""

# ── P3 보강: 실제 접두사 이름으로 ─────────────────────────────────────
log "P3 보강: Always 모드 실제 접두사(mcp-b-80_)"
note "## P3 보강. Always 모드, 실제 재작명 이름"
note ""
kubectl --context $CTX -n $NS patch agentgatewaybackend mcp-b-stateless --type merge \
  -p '{"spec":{"mcp":{"prefixMode":"Always"}}}' >/dev/null 2>&1
sleep 12
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
kubectl --context $CTX -n $NS patch agentgatewaybackend mcp-b-stateless --type merge \
  -p '{"spec":{"mcp":{"prefixMode":"Conditional"}}}' >/dev/null 2>&1
sleep 12
note ""
note "판정 기준: 원명 정책 아래 mcp-b-80_get-sum이 통과하면 재작명 우회가 실재한다."
note "mcp-b-80_echo가 어느 정책에서 통과하는지가 정책이 보는 이름을 확정한다."

# ── T1 유효 재측정 ────────────────────────────────────────────────────
log "T1: traceparent 전파 N=5 (버그 수정 후 첫 유효 측정)"
note ""
note "## T1 재측정. traceparent 전파 (N=5)"
note ""
kubectl --context $CTX -n $NS patch agentgatewaybackend mcp-b-stateless --type merge \
  -p '{"spec":{"mcp":{"targets":[{"name":"tap-proxy","selector":{"services":{"matchLabels":{"app":"tap-proxy"}}}}]}}}' >/dev/null 2>&1
sleep 15
for n in 1 2 3 4 5; do
  TP="00-4bf92f3577b34da6a3ce929d0e0e473$n-00f067aa0ba902b$n-01"
  RES=$(call /b echo "" "{\"traceparent\": \"$TP\"}")
  sleep 3
  TAPPED=$(kubectl --context $CTX -n $NS logs deploy/tap-proxy 2>/dev/null | grep '"tap"' | tail -1 | head -c 400)
  note "- n$n 보낸 값 \`$TP\`"
  note "  - 게이트웨이 응답: \`$RES\`"
  note "  - 탭이 받은 것: \`${TAPPED:-없음}\`"
done
note ""
note "판정 기준: 탭 headers에 traceparent가 있으면 전파, 없으면 게이트웨이가 끊는 것."
note "이번에는 게이트웨이 응답이 비어 있지 않아야 프로브가 유효하다."
kubectl --context $CTX -n $NS logs deploy/tap-proxy 2>/dev/null | grep '"tap"' | tail -40 > "$OUT/tap-log.txt"

# ── 정리 ─────────────────────────────────────────────────────────────
log "정리: 백엔드 원복, 탭과 agentgateway 제거"
kubectl --context $CTX -n $NS patch agentgatewaybackend mcp-b-stateless --type merge \
  -p '{"spec":{"mcp":{"targets":[{"name":"mcp-b","selector":{"services":{"matchLabels":{"app":"mcp-b"}}}}]}}}' >/dev/null 2>&1
kubectl --context $CTX delete -f "$MCPSTUDY/k8s/tap-proxy.yaml" >/dev/null 2>&1
bash "$GWDIR/uninstall.sh" >> "$OUT/install.log" 2>&1
note ""
note "---"
note "정리 완료. 게이트웨이와 탭을 제거해 격리 상태로 되돌렸다."
log "=== 보강 완료: $OUT ==="
