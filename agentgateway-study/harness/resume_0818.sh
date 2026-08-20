#!/usr/bin/env bash
# 일회성 재개 스크립트 (2026-08-18). run_axes.sh가 P4 규칙 21개 구간에서 외부
# 요인으로 중단됐다(30셀 중 24셀 완료, 게이트웨이는 설치된 채 남음). 남은 6셀
# (r21-rps100-n5, r21-rps200-n1~5)과 T1/T2, 정리를 이어서 실행하고 같은
# FINDINGS.md에 이어 붙인다. 완주 후에는 쓸 일이 없다.
# 사용: ./resume_0818.sh <PYTHON> <OUT_DIR>
set -uo pipefail

PY="$1"; OUT="$2"
CTX="mcp-migration"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCPSTUDY="$(cd "$DIR/../../mcp-migration/studies/stateless-scaleout" && pwd)"
GWDIR="$MCPSTUDY/k8s/agentgateway"
LOADGEN="$MCPSTUDY/harness/loadgen.py"

log() { echo "[$(date '+%m-%d %H:%M')] $*"; }
note() { echo "$*" >> "$OUT/FINDINGS.md"; }

GW=$(kubectl --context $CTX -n agentgateway-system get gateway agentgateway-proxy -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
[ -z "$GW" ] && { log "[중단] 게이트웨이 주소 없음"; exit 1; }
GW="http://$GW"

call() { # call <path> <tool> [args-json] [extra-header-json]
  "$PY" - "$GW" "$1" "$2" "${3:-null}" "${4:-{}}" <<'PYEOF'
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

p4_cell() { # p4_cell <name> <rps> <concurrency>
  "$PY" "$LOADGEN" --url "$GW/b" --dialect b --tool echo \
    --concurrency "$3" --duration 30 --conn-mode close --rps "$2" \
    --out "$OUT/$1.json" >/dev/null 2>&1
  "$PY" -c "
import json
d=json.load(open('$OUT/$1.json'))
print(f\"achieved={d['achieved_rps']:.1f} p50={d['latency_ms']['p50']:.1f} p99={d['latency_ms']['p99']:.1f}\")"
}

# ── P4 잔여 6셀: 규칙 21개 ────────────────────────────────────────────
log "P4 재개: 규칙 21개 잔여 셀"
RULES=""
for i in $(seq 1 20); do RULES="$RULES            - mcp.tool.name == \"tool$i\"
"; done
RULES="$RULES            - mcp.tool.name == \"echo\""
apply_policy ax-p4 "$RULES"
R=$(p4_cell "p4-r21-rps100-n5" 100 8)
note "  - n5: $R (재개 후)"
sleep 60
note "- 규칙 21개, 200rps:"
for n in 1 2 3 4 5; do
  R=$(p4_cell "p4-r21-rps200-n${n}" 200 16)
  note "  - n$n: $R"
  sleep 60
done
drop_policy ax-p4
note ""
note "판정 기준: 규칙 수와 rps에 따라 p50과 p99가 어떻게 움직이는지. 회차 편차도 본다."
note "(중단 사고: 규칙 21개 100rps n5 직전에 외부 요인으로 프로세스가 죽어 n5부터"
note "재개 스크립트로 이어 측정했다. 게이트웨이와 정책 구성은 동일하게 유지됐다.)"

# ── T1/T2: traceparent 전파 (N=5) ─────────────────────────────────────
log "T1/T2: traceparent 전파 N=5"
note ""
note "## T1. traceparent 전파 (N=5)"
note ""
kubectl --context $CTX -n $NS patch agentgatewaybackend mcp-b-stateless --type merge \
  -p '{"spec":{"mcp":{"targets":[{"name":"tap-proxy","selector":{"services":{"matchLabels":{"app":"tap-proxy"}}}}]}}}' >/dev/null 2>&1
sleep 15
for n in 1 2 3 4 5; do
  TP="00-4bf92f3577b34da6a3ce929d0e0e473$n-00f067aa0ba902b$n-01"
  RES=$(call /b echo null "{\"traceparent\": \"$TP\"}")
  sleep 3
  TAPPED=$(kubectl --context $CTX -n $NS logs deploy/tap-proxy 2>/dev/null | grep '"tap"' | tail -1 | head -c 400)
  note "- n$n 보낸 값 \`$TP\`"
  note "  - 게이트웨이 응답: \`$RES\`"
  note "  - 탭이 받은 것: \`${TAPPED:-없음}\`"
done
note ""
note "## T2. 탭에 도달한 헤더와 params._meta 원문"
note ""
note "판정 기준: headers에 traceparent가 있으면 전파, 없으면 게이트웨이가 끊는 것."
note "params_meta 안 트레이스 키 유무도 본다(스펙 예약 자리). 원문은 tap-log.txt."
kubectl --context $CTX -n $NS logs deploy/tap-proxy 2>/dev/null | grep '"tap"' | tail -40 > "$OUT/tap-log.txt"

# ── 정리 ─────────────────────────────────────────────────────────────
log "정리: 탭 제거하고 백엔드 원복, agentgateway 제거"
kubectl --context $CTX -n $NS patch agentgatewaybackend mcp-b-stateless --type merge \
  -p '{"spec":{"mcp":{"targets":[{"name":"mcp-b","selector":{"services":{"matchLabels":{"app":"mcp-b"}}}}]}}}' >/dev/null 2>&1
kubectl --context $CTX delete -f "$MCPSTUDY/k8s/tap-proxy.yaml" >/dev/null 2>&1
bash "$GWDIR/uninstall.sh" >> "$OUT/install.log" 2>&1
note ""
note "---"
note ""
note "정리 완료. 게이트웨이와 탭을 제거해 격리 상태로 되돌렸다."
log "=== 재개분 완료: $OUT ==="
