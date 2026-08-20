#!/usr/bin/env bash
# 축 1(정책 강제)과 축 2(관측) 본측정. DESIGN.md의 셀 구성을 그대로 구현한다.
# run_week5.sh(스파이크)를 승격 개작한 것이다. 반영한 수정:
#   - 게이트웨이 주소는 agentgateway-system 네임스페이스에서 받고 URL에 스킴을 붙인다
#   - tools/list의 SSE 응답 파싱 (스파이크에서 전량 파싱 실패했던 구멍)
#   - P2: a=1 / a=2 / 무관 도구 프로브 (스파이크는 a=1뿐이었다)
#   - P3: prefixMode 3종 x 정책 대상 이름(원명/접두사명) 2종 x 호출 이름 4종
#   - P4: 규칙 0/1/21 x rps 100/200 x N=5 (스파이크는 100rps 1회)
#   - T1: traceparent 프로브 N=5
#
# 인프라는 mcp-migration 자산을 상대경로로 재사용한다(복제 금지).
# 사용: ./run_axes.sh <PYTHON> <OUT_DIR>
set -uo pipefail

PY="$1"; OUT="$2"
CTX="mcp-migration"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCPSTUDY="$(cd "$DIR/../../mcp-migration/studies/stateless-scaleout" && pwd)"
GWDIR="$MCPSTUDY/k8s/agentgateway"
LOADGEN="$MCPSTUDY/harness/loadgen.py"
mkdir -p "$OUT"

log() { echo "[$(date '+%m-%d %H:%M')] $*"; }
note() { echo "$*" >> "$OUT/FINDINGS.md"; }

echo "# agentgateway-study 축 1/2 본측정 (자동 생성)" > "$OUT/FINDINGS.md"
note ""
note "실행 $(date '+%Y-%m-%d %H:%M'). 셀 구성은 DESIGN.md. 판정은 사람이 한다."
note ""

# ── 준비 ──────────────────────────────────────────────────────────────
log "agentgateway v1.4.1 설치"
AGW_VER=v1.4.1 bash "$GWDIR/install.sh" > "$OUT/install.log" 2>&1
sleep 30
kubectl --context $CTX apply -f "$GWDIR/gateway.yaml" >> "$OUT/install.log" 2>&1
kubectl --context $CTX apply -f "$MCPSTUDY/k8s/tap-proxy.yaml" >> "$OUT/install.log" 2>&1
kubectl --context $CTX -n $NS rollout status deploy/tap-proxy --timeout=180s >> "$OUT/install.log" 2>&1
kubectl --context $CTX -n $NS scale deploy/mcp-a --replicas=1 >/dev/null 2>&1
kubectl --context $CTX -n $NS scale deploy/mcp-b --replicas=1 >/dev/null 2>&1
sleep 20
GW=$(kubectl --context $CTX -n agentgateway-system get gateway agentgateway-proxy -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
log "게이트웨이 주소: ${GW:-없음}"
[ -z "$GW" ] && { log "[중단] 게이트웨이 주소를 못 받았다"; note "**중단**: 게이트웨이 주소 없음"; exit 1; }
GW="http://$GW"

call() { # call <path> <tool> [args-json] [extra-header-json]
  # 주의: "${4:-{}}"는 첫 }가 확장을 닫아 인자 뒤에 }가 붙는다. 명시 분기로 처리.
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

list_tools() { # SSE(event/data 줄)와 순수 JSON 둘 다 파싱한다
  "$PY" - "$GW" "$1" <<'PYEOF'
import json, sys, httpx
gw, path = sys.argv[1], sys.argv[2]
h = {"Accept": "application/json, text/event-stream", "Content-Type": "application/json",
     "MCP-Protocol-Version": "2026-07-28", "Mcp-Method": "tools/list"}
try:
    r = httpx.post(f"{gw}{path}", headers=h, timeout=20, json={"jsonrpc": "2.0", "id": 1,
        "method": "tools/list", "params": {"_meta": {
            "io.modelcontextprotocol/protocolVersion": "2026-07-28",
            "io.modelcontextprotocol/clientInfo": {"name": "axes", "version": "0.1"},
            "io.modelcontextprotocol/clientCapabilities": {}}}})
    doc = None
    try:
        doc = r.json()
    except Exception:
        for line in r.text.splitlines():
            if line.startswith("data:"):
                doc = json.loads(line[5:].strip())
                break
    if doc is None:
        raise ValueError(f"unparsed: {r.text[:120]!r}")
    if "error" in doc:
        print(json.dumps({"status": r.status_code, "error": doc["error"]}, ensure_ascii=False))
    else:
        names = [t.get("name") for t in (doc.get("result") or {}).get("tools", [])]
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

set_prefix() { # set_prefix <mode>
  kubectl --context $CTX -n $NS patch agentgatewaybackend mcp-b-stateless --type merge \
    -p "{\"spec\":{\"mcp\":{\"prefixMode\":\"$1\"}}}" >/dev/null 2>&1
  sleep 12
}

# ── P0: 정책 없음 기준선 ──────────────────────────────────────────────
log "=== P0: 정책 없음 기준선 ==="
note "## P0. 정책 없음 기준선"
note ""
note "- tools/list: \`$(list_tools /b)\`"
note "- echo: \`$(call /b echo)\`"
note "- get-sum: \`$(call /b get-sum)\`"

# ── P1: 화이트리스트와 목록 필터링 ────────────────────────────────────
log "=== P1: 화이트리스트 강제 + 목록 필터링 ==="
note ""
note "## P1. 화이트리스트 (echo만 허용)"
note ""
apply_policy ax-allow-echo '            - mcp.tool.name == "echo"'
note "- tools/list(차단 도구가 사라지는지): \`$(list_tools /b)\`"
note "- echo 호출(허용 기대): \`$(call /b echo)\`"
note "- get-sum 호출(차단 기대): \`$(call /b get-sum)\`"
note ""
note "판정 기준: 차단이 강제되는가. 그리고 tools/list에서 get-sum이 사라지는가"
note "(사라지면 목록 필터링까지 하는 것이고, 남는데 호출만 막히면 은닉이 아니라 거부다)."
drop_policy ax-allow-echo

# ── P2: 인자 조건 정책 (핵심 발견 셀) ─────────────────────────────────
log "=== P2: 인자 조건 정책 ==="
note ""
note "## P2. 인자 조건 정책 (핵심 발견 셀)"
note ""
note "정책: \`mcp.tool.name == \"get-sum\" && mcp.tool.arguments.a == 1\` 하나만 허용."
note "스파이크에서 정책이 수용되는데 조건 참 호출도 차단됨을 봤다. 세 프로브로 확정한다."
apply_policy ax-arg-test '            - mcp.tool.name == "get-sum" && mcp.tool.arguments.a == 1'
P2_STATE=$(kubectl --context $CTX -n $NS get agentgatewaypolicy ax-arg-test -o json 2>/dev/null \
  | "$PY" -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d.get('status',{}), ensure_ascii=False)[:600])")
note "- 정책 리소스 status: \`${P2_STATE:-비어 있음}\`"
note "- get-sum, a=1 (조건 참): \`$(call /b get-sum '{"a": 1, "b": 2}')\`"
note "- get-sum, a=2 (조건 거짓): \`$(call /b get-sum '{"a": 2, "b": 2}')\`"
note "- echo (규칙 무관 도구): \`$(call /b echo)\`"
note ""
note "판정 기준: a=1과 a=2가 똑같이 차단되면 '수용되지만 인자가 평가되지 않아 전량"
note "차단'이 확정된다. a=1만 통과하면 조사 결론이 틀린 것이다. echo 차단 여부는"
note "matchExpressions가 화이트리스트(목록 밖 전부 거부)로 동작하는지의 근거다."
drop_policy ax-arg-test

# ── P3: prefixMode x 정책 대상 이름 x 호출 이름 ───────────────────────
log "=== P3: prefixMode x 정책 이름 전조합 ==="
note ""
note "## P3. prefixMode와 정책의 상호작용"
note ""
note "정책이 원래 이름을 보는지 재작명된 이름을 보는지 확정한다. 각 모드에서"
note "tools/list로 실제 노출 이름을 먼저 확인하고, 정책 2종(원명 echo 허용 / 접두사명"
note "mcp-b_echo 허용) 아래에서 이름 4종을 호출한다."
for mode in Conditional Always Never; do
  set_prefix "$mode"
  note ""
  note "### prefixMode=$mode"
  note "- 정책 없음, tools/list(노출 이름): \`$(list_tools /b)\`"
  for pol in bare prefixed; do
    if [ "$pol" = bare ]; then
      apply_policy ax-p3 '            - mcp.tool.name == "echo"'
      note "- 정책 = 원명 \`echo\` 허용"
    else
      apply_policy ax-p3 '            - mcp.tool.name == "mcp-b_echo"'
      note "- 정책 = 접두사명 \`mcp-b_echo\` 허용"
    fi
    for tool in echo mcp-b_echo get-sum mcp-b_get-sum; do
      note "  - $tool 호출: \`$(call /b "$tool")\`"
    done
    drop_policy ax-p3
  done
done
set_prefix Conditional
note ""
note "판정 기준: 어느 조합에서든 get-sum 계열이 통과하면 우회다. 허용 도구가 어느"
note "이름으로 통과하는지가 정책이 보는 이름(원명 대 재작명명)을 확정한다."

# ── P4: 정책 지연 오버헤드 (규칙 수 x rps x 반복) ─────────────────────
log "=== P4: 오버헤드 규칙 0/1/21 x rps 100/200 x N=5 ==="
note ""
note "## P4. 정책 지연 오버헤드"
note ""
note "규칙 0/1/21개 x rps 100/200 x N=5, 30초 close 모드, 회차 간 60초 쿨다운."
note ""
p4_cell() { # p4_cell <name> <rps> <concurrency>
  "$PY" "$LOADGEN" --url "$GW/b" --dialect b --tool echo \
    --concurrency "$3" --duration 30 --conn-mode close --rps "$2" \
    --out "$OUT/$1.json" >/dev/null 2>&1
  "$PY" -c "
import json
d=json.load(open('$OUT/$1.json'))
print(f\"achieved={d['achieved_rps']:.1f} p50={d['latency_ms']['p50']:.1f} p99={d['latency_ms']['p99']:.1f}\")"
}
RULES=""
for i in $(seq 1 20); do RULES="$RULES            - mcp.tool.name == \"tool$i\"
"; done
RULES="$RULES            - mcp.tool.name == \"echo\""
for nrules in 0 1 21; do
  case $nrules in
    0) : ;;
    1) apply_policy ax-p4 '            - mcp.tool.name == "echo"' ;;
    21) apply_policy ax-p4 "$RULES" ;;
  esac
  for rps in 100 200; do
    conc=8; [ "$rps" = 200 ] && conc=16
    note "- 규칙 ${nrules}개, ${rps}rps:"
    for n in 1 2 3 4 5; do
      R=$(p4_cell "p4-r${nrules}-rps${rps}-n${n}" "$rps" "$conc")
      note "  - n$n: $R"
      sleep 60
    done
  done
  [ "$nrules" != 0 ] && drop_policy ax-p4
done
note ""
note "판정 기준: 규칙 수와 rps에 따라 p50과 p99가 어떻게 움직이는지. 회차 편차도 본다."

# ── T1/T2: traceparent 전파 (N=5) + _meta 트레이스 키 ─────────────────
log "=== T1/T2: traceparent 전파 N=5 ==="
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
log "=== 본측정 완료: $OUT ==="
