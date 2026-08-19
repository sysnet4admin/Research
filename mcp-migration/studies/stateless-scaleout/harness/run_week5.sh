#!/usr/bin/env bash
# 보강 주간 5부: agentgateway 스파이크 (2026-08-10 추가).
# run_week4.sh 가 끝나면 이어서 돈다. 결과는 8/18 아침에 확인한다.
#
# 목적은 측정이 아니라 **연구 후보의 착수 게이트 확인**이다.
# `_CANDIDATES/agentgateway-study.md`가 제안한 두 축을 실물로 검증한다.
#
#   G1  도구 이름 화이트리스트가 선언대로 강제되는가
#   G2  prefixMode 재작명이 정책을 우회하는가 (소스에서 필터링과 리네임 순서를
#       다 못 봤다. 동작으로 확인한다)
#   G3  도구 인자 기반 정책이 정말 표현 불가능한가 (핵심 발견 후보의 실증)
#   G4  정책 유무와 규칙 개수에 따른 지연 오버헤드
#   G5  traceparent가 게이트웨이를 넘어 다운스트림까지 가는가
#
# 3부의 재현 검증(V8)이 스냅샷을 복원하면서 agentgateway를 지우므로 재설치부터 한다.
#
# 사용: ./run_week5.sh <PYTHON> <OUT_DIR>
set -uo pipefail

PY="$1"; OUT="$2"
CTX="mcp-migration"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
GWDIR="$STUDY/k8s/agentgateway"
mkdir -p "$OUT"

log() { echo "[$(date '+%m-%d %H:%M')] $*"; }
note() { echo "$*" >> "$OUT/FINDINGS.md"; }

while pgrep -f run_week4.sh >/dev/null; do sleep 60; done
log "4부 종료 확인. 5부(agentgateway 스파이크) 시작"

echo "# agentgateway 스파이크 결과 (자동 생성)" > "$OUT/FINDINGS.md"
note ""
note "실행 $(date '+%Y-%m-%d %H:%M'). 목적은 \`_CANDIDATES/agentgateway-study.md\`의"
note "착수 게이트 확인이다. 판정은 사람이 한다."
note ""

# ── 준비 ──────────────────────────────────────────────────────────────
log "agentgateway v1.4.1 재설치"
AGW_VER=v1.4.1 bash "$GWDIR/install.sh" > "$OUT/install.log" 2>&1
sleep 30
kubectl --context $CTX apply -f "$GWDIR/gateway.yaml" >> "$OUT/install.log" 2>&1
kubectl --context $CTX apply -f "$STUDY/k8s/tap-proxy.yaml" >> "$OUT/install.log" 2>&1
kubectl --context $CTX -n $NS rollout status deploy/tap-proxy --timeout=180s >> "$OUT/install.log" 2>&1
kubectl --context $CTX -n $NS scale deploy/mcp-a --replicas=1 >/dev/null 2>&1
kubectl --context $CTX -n $NS scale deploy/mcp-b --replicas=1 >/dev/null 2>&1
sleep 20
GW=$(kubectl --context $CTX -n agentgateway-system get gateway agentgateway-proxy -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
log "게이트웨이 주소: ${GW:-없음}"
[ -z "$GW" ] && { log "[중단] 게이트웨이 주소를 못 받았다"; note "**중단**: 게이트웨이 주소 없음"; exit 1; }
GW="http://$GW"   # jsonpath는 맨 IP를 주므로 스킴을 붙인다 (httpx, loadgen 모두 완전한 URL 요구)

call() { # call <path> <tool> [extra-header-json]
  "$PY" - "$GW" "$1" "$2" "${3:-{}}" <<'PYEOF'
import json, sys, httpx
gw, path, tool, extra = sys.argv[1], sys.argv[2], sys.argv[3], json.loads(sys.argv[4])
h = {"Accept": "application/json, text/event-stream", "Content-Type": "application/json",
     "MCP-Protocol-Version": "2026-07-28", "Mcp-Method": "tools/call", "Mcp-Name": tool}
h.update(extra)
args = {"message": "ping"} if tool.endswith("echo") else ({"a": 1, "b": 2} if "sum" in tool else {})
body = {"jsonrpc": "2.0", "id": 1, "method": "tools/call",
        "params": {"name": tool, "arguments": args,
                   "_meta": {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
                             "io.modelcontextprotocol/clientInfo": {"name": "spike", "version": "0.1"},
                             "io.modelcontextprotocol/clientCapabilities": {}}}}
try:
    r = httpx.post(f"{gw}{path}", headers=h, json=body, timeout=20)
    txt = r.text[:220].replace("\n", " ")
    print(json.dumps({"status": r.status_code, "body": txt}, ensure_ascii=False))
except Exception as e:
    print(json.dumps({"status": 0, "body": f"{type(e).__name__}: {e}"}, ensure_ascii=False))
PYEOF
}

list_tools() {
  "$PY" - "$GW" "$1" <<'PYEOF'
import json, sys, httpx
gw, path = sys.argv[1], sys.argv[2]
h = {"Accept": "application/json, text/event-stream", "Content-Type": "application/json",
     "MCP-Protocol-Version": "2026-07-28", "Mcp-Method": "tools/list"}
try:
    r = httpx.post(f"{gw}{path}", headers=h, timeout=20, json={"jsonrpc": "2.0", "id": 1,
        "method": "tools/list", "params": {"_meta": {
            "io.modelcontextprotocol/protocolVersion": "2026-07-28",
            "io.modelcontextprotocol/clientInfo": {"name": "spike", "version": "0.1"},
            "io.modelcontextprotocol/clientCapabilities": {}}}})
    names = [t.get("name") for t in (r.json().get("result") or {}).get("tools", [])]
    print(json.dumps({"status": r.status_code, "tools": names}, ensure_ascii=False))
except Exception as e:
    print(json.dumps({"status": 0, "tools": [], "err": str(e)}, ensure_ascii=False))
PYEOF
}

apply_policy() { # apply_policy <name> <matchExpressions yaml block>
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

# ── G1: 도구 이름 화이트리스트 강제 ──────────────────────────────────
log "=== G1: 도구 이름 화이트리스트가 강제되는가 ==="
note "## G1. 도구 이름 화이트리스트"
note ""
note '정책 없이 먼저 본다.'
BEFORE_LIST=$(list_tools /b); BEFORE_ECHO=$(call /b echo); BEFORE_SUM=$(call /b get-sum)
note "- 정책 없음, tools/list: \`$BEFORE_LIST\`"
note "- 정책 없음, echo 호출: \`$BEFORE_ECHO\`"
note "- 정책 없음, get-sum 호출: \`$BEFORE_SUM\`"

apply_policy mcp-allow-echo '            - mcp.tool.name == "echo"'
AFTER_LIST=$(list_tools /b); AFTER_ECHO=$(call /b echo); AFTER_SUM=$(call /b get-sum)
note ""
note 'echo만 허용하는 정책을 붙인 뒤.'
note "- tools/list: \`$AFTER_LIST\`"
note "- echo 호출(허용 기대): \`$AFTER_ECHO\`"
note "- get-sum 호출(차단 기대): \`$AFTER_SUM\`"
note ""
note "판정 기준: get-sum이 차단되면 강제된다. 통과하면 문서와 실제가 어긋난다."
note "tools/list에서 get-sum이 사라지는지도 별개 관심사다(목록 필터링 여부)."

# ── G2: prefixMode 재작명이 우회가 되는가 ────────────────────────────
log "=== G2: prefixMode 재작명이 정책을 우회하는가 ==="
note ""
note "## G2. prefixMode 재작명 우회"
note ""
note "소스에서 인가 필터링과 이름 재작명의 순서를 다 확인하지 못했다. 동작으로 본다."
for mode in Conditional Always Never; do
  kubectl --context $CTX -n $NS patch agentgatewaybackend mcp-b-stateless --type merge \
    -p "{\"spec\":{\"mcp\":{\"prefixMode\":\"$mode\"}}}" >/dev/null 2>&1
  sleep 12
  L=$(list_tools /b); E=$(call /b echo); S=$(call /b get-sum)
  note "- prefixMode=$mode"
  note "  - tools/list: \`$L\`"
  note "  - echo: \`$E\`"
  note "  - get-sum: \`$S\`"
  # 접두사가 붙은 이름으로도 시도한다
  PS=$(call /b "mcp-b_get-sum")
  note "  - 접두사 이름 get-sum 시도: \`$PS\`"
done
kubectl --context $CTX -n $NS patch agentgatewaybackend mcp-b-stateless --type merge \
  -p '{"spec":{"mcp":{"prefixMode":"Conditional"}}}' >/dev/null 2>&1
sleep 10
note ""
note "판정 기준: 어느 모드에서든 접두사 이름으로 get-sum이 통과하면 우회 경로다."

# ── G3: 인자 기반 정책이 표현 가능한가 ───────────────────────────────
log "=== G3: 도구 인자 기반 정책이 표현 가능한가 ==="
drop_policy mcp-allow-echo
note ""
note "## G3. 인자 기반 정책 (핵심 발견 후보)"
note ""
note "조사 결론은 '인가 평가 시점에 인자가 컨텍스트에 없다'였다. 실물로 확인한다."
apply_policy mcp-arg-test '            - mcp.tool.name == "get-sum" && mcp.tool.arguments.a == 1'
ARG_STATE=$(kubectl --context $CTX -n $NS get agentgatewaypolicy mcp-arg-test \
  -o jsonpath='{.status}' 2>/dev/null | head -c 400)
ARG_CALL_MATCH=$(call /b get-sum)
note "- 정책 리소스 status: \`${ARG_STATE:-비어 있음}\`"
note "- 조건에 맞는 인자(a=1)로 get-sum 호출: \`$ARG_CALL_MATCH\`"
note ""
note "판정 기준 셋. (a) 정책이 아예 거절되면(status에 오류) 표현 불가가 명확하다."
note "(b) 수용되지만 조건과 무관하게 전부 통과하면 인자를 못 보는 것이다."
note "(c) 조건대로 갈리면 조사 결론이 틀린 것이므로 재조사가 필요하다."
drop_policy mcp-arg-test

# ── G4: 정책 지연 오버헤드 ───────────────────────────────────────────
log "=== G4: 정책 지연 오버헤드 ==="
note ""
note "## G4. 정책 지연 오버헤드"
note ""
cell() { # cell <name>
  "$PY" "$DIR/loadgen.py" --url "$GW/b" --dialect b --tool echo \
    --concurrency 8 --duration 30 --conn-mode close --rps 100 \
    --out "$OUT/$1.json" >/dev/null 2>&1
  python3 -c "
import json
d=json.load(open('$OUT/$1.json'))
print(f\"rps={d['achieved_rps']:.1f} p50={d['latency_ms']['p50']:.1f} p99={d['latency_ms']['p99']:.1f}\")"
}
R0=$(cell g4-no-policy); note "- 정책 없음: $R0"; sleep 60
apply_policy mcp-p1 '            - mcp.tool.name == "echo"'
R1=$(cell g4-1rule); note "- 규칙 1개: $R1"; sleep 60
RULES=""
for i in $(seq 1 20); do RULES="$RULES            - mcp.tool.name == \"tool$i\"
"; done
RULES="$RULES            - mcp.tool.name == \"echo\""
drop_policy mcp-p1
apply_policy mcp-p20 "$RULES"
R20=$(cell g4-21rules); note "- 규칙 21개: $R20"
drop_policy mcp-p20
note ""
note "판정 기준: 규칙이 늘 때 p50과 p99가 어떻게 움직이는지 본다."

# ── G5: traceparent 전파 ─────────────────────────────────────────────
log "=== G5: traceparent가 다운스트림까지 가는가 ==="
note ""
note "## G5. traceparent 전파"
note ""
note "MCP 스펙이 \`_meta\`에 W3C Trace Context를 예약했는데 게이트웨이가 잇는지"
note "문서에 없다. 탭 프록시를 게이트웨이 뒤에 두고 무엇이 넘어오는지 본다."
kubectl --context $CTX -n $NS patch agentgatewaybackend mcp-b-stateless --type merge \
  -p '{"spec":{"mcp":{"targets":[{"name":"tap-proxy","selector":{"services":{"matchLabels":{"app":"tap-proxy"}}}}]}}}' >/dev/null 2>&1
sleep 15
TP="00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
kubectl --context $CTX -n $NS logs deploy/tap-proxy --tail=1 >/dev/null 2>&1
BEFORE_N=$(kubectl --context $CTX -n $NS logs deploy/tap-proxy 2>/dev/null | grep -c '"tap"')
RES=$(call /b echo "{\"traceparent\": \"$TP\"}")
sleep 5
TAPPED=$(kubectl --context $CTX -n $NS logs deploy/tap-proxy 2>/dev/null | grep '"tap"' | tail -1)
note "- 클라이언트가 보낸 traceparent: \`$TP\`"
note "- 게이트웨이 응답: \`$RES\`"
note "- 탭이 받은 것: \`${TAPPED:-없음}\`"
note ""
note "판정 기준: 탭 로그의 headers에 traceparent가 그대로 있으면 전파된다."
note "없으면 게이트웨이가 끊는 것이고, 그 자체가 발견이다. params_meta에 트레이스"
note "키가 있는지도 함께 본다(스펙이 예약한 자리)."
kubectl --context $CTX -n $NS logs deploy/tap-proxy 2>/dev/null | grep '"tap"' | tail -20 > "$OUT/tap-log.txt"

# ── 정리 ─────────────────────────────────────────────────────────────
log "정리: 탭 제거하고 백엔드 원복, agentgateway 제거"
kubectl --context $CTX -n $NS patch agentgatewaybackend mcp-b-stateless --type merge \
  -p '{"spec":{"mcp":{"targets":[{"name":"mcp-b","selector":{"services":{"matchLabels":{"app":"mcp-b"}}}}]}}}' >/dev/null 2>&1
kubectl --context $CTX delete -f "$STUDY/k8s/tap-proxy.yaml" >/dev/null 2>&1
bash "$GWDIR/uninstall.sh" >> "$OUT/install.log" 2>&1
note ""
note "---"
note ""
note "정리 완료. 게이트웨이와 탭을 제거해 격리 상태로 되돌렸다."
note "이 결과로 \`_CANDIDATES/agentgateway-study.md\`의 착수 게이트를 판정한다."
log "=== 5부 완료: $OUT ==="
