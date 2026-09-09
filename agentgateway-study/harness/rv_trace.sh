#!/usr/bin/env bash
# 트레이싱을 켠 경로 측정 (README 한계 "트레이싱 켠 경로 미측정" 해소).
# rv_run_ab.sh의 셀 구조를 그대로 쓰고 정책만 켰다 껐다 한다(수집기는 내내 상주).
#
#  T-A. 스팬 부모 관계: MCP 백엔드와 일반 HTTP 백엔드에 같은 traceparent를 보내고
#       수집기 로그에서 게이트웨이 스팬과 업스트림 스팬의 부모를 읽는다(#2904 재확인).
#  T-B. 비용: 트레이싱 끔 대 켬을 close/reuse 모드에서 교대로 잰다.
#
# 사용: ./rv_trace.sh <PYTHON> <OUT_DIR>
# 조절: RV_ROUNDS(기본 3) RV_DURATION(30) RV_COOLDOWN(180)
set -uo pipefail

PY="$1"; OUT_REL="$2"
CTX="aaif-benchmark"; NS="mcp-pilot"; AGWNS="agentgateway-system"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
MCPSTUDY="$(cd "$STUDY/../mcp-migration/studies/stateless-scaleout" && pwd)"
LOADGEN="$MCPSTUDY/harness/loadgen.py"
ROUNDS="${RV_ROUNDS:-3}"; DUR="${RV_DURATION:-30}"; COOLDOWN="${RV_COOLDOWN:-180}"
OUT="$STUDY/$OUT_REL"; mkdir -p "$OUT"
log() { echo "[trace $(date '+%m-%d %H:%M')] $*"; }
note() { echo "$*" >> "$OUT/FINDINGS.md"; }

GW=$(kubectl --context $CTX -n $AGWNS get gateway agentgateway-proxy -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
[ -z "$GW" ] && { log "[중단] 게이트웨이 주소 없음"; exit 1; }
AGWV=$(kubectl --context $CTX -n $AGWNS get deploy agentgateway-proxy -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | sed 's/.*://')
DIRECT_IP=$(kubectl --context $CTX -n $NS get svc mcp-b -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

echo "# 트레이싱 켠 경로 측정 (자동 생성, agentgateway $AGWV)" > "$OUT/FINDINGS.md"
note ""
note "실행 $(date '+%Y-%m-%d %H:%M'). 컨텍스트 $CTX. 수집기는 내내 상주하고 트레이싱 정책만 켰다 껐다 한다."
note "부하 ${ROUNDS}회 x ${DUR}초, 셀 간 쿨다운 ${COOLDOWN}초."
note ""

apply_tracing() {
  cat <<YAML | kubectl --context $CTX apply -f - >> "$OUT/apply.log" 2>&1
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata:
  name: rv-tracing
  namespace: agentgateway-system
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: agentgateway-proxy
  frontend:
    tracing:
      backendRef:
        kind: Service
        name: otel-collector
        namespace: agentgateway-system
        port: 4317
      protocol: GRPC
      randomSampling: "1.0"
YAML
  sleep 12
}
delete_tracing() { kubectl --context $CTX -n $AGWNS delete agentgatewaypolicy rv-tracing >/dev/null 2>&1; sleep 8; }
cleanup() {
  delete_tracing
  kubectl --context $CTX -n $NS delete httproute plain-b >/dev/null 2>&1
  kubectl --context $CTX delete -f "$STUDY/k8s/tracing/otel-collector.yaml" >/dev/null 2>&1
  log "정리 완료(수집기, 정책, 임시 라우트 제거)"
}
trap cleanup EXIT

# ── 수집기 배포 ───────────────────────────────────────────────────────
log "OTel 수집기 배포"
kubectl --context $CTX apply -f "$STUDY/k8s/tracing/otel-collector.yaml" > "$OUT/apply.log" 2>&1
kubectl --context $CTX -n $AGWNS rollout status deploy/otel-collector --timeout=300s >> "$OUT/apply.log" 2>&1 \
  || { log "[중단] 수집기 기동 실패"; note "**중단**: 수집기 기동 실패"; exit 1; }
sleep 5

# ── T-A. 스팬 부모 관계 ───────────────────────────────────────────────
log "T-A: 스팬 부모 관계"
cat <<YAML | kubectl --context $CTX apply -f - >> "$OUT/apply.log" 2>&1
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: plain-b
  namespace: mcp-pilot
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: agentgateway-proxy
      namespace: agentgateway-system
  rules:
    - matches:
        - path: { type: PathPrefix, value: /plain }
      backendRefs:
        - name: mcp-b
          port: 80
YAML
sleep 10
apply_tracing
note "## T-A. 스팬 부모 관계 (MCP 백엔드 대 일반 HTTP 백엔드)"
note ""
note "- 정책 상태: $(kubectl --context $CTX -n $AGWNS get agentgatewaypolicy rv-tracing -o jsonpath='Accepted={.status.ancestors[0].conditions[?(@.type=="Accepted")].status} Attached={.status.ancestors[0].conditions[?(@.type=="Attached")].status}' 2>/dev/null)"
kubectl --context $CTX -n $AGWNS logs deploy/otel-collector --tail=1 >/dev/null 2>&1
SINCE=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
for n in 1 2 3; do
  TP="00-$(openssl rand -hex 16)-$(openssl rand -hex 8)-01"
  curl -s -o /dev/null --max-time 8 -X POST "http://$GW/b" \
    -H 'Accept: application/json, text/event-stream' -H 'Content-Type: application/json' \
    -H 'MCP-Protocol-Version: 2026-07-28' -H 'Mcp-Method: tools/call' -H 'Mcp-Name: echo' \
    -H "traceparent: $TP" \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo","arguments":{"message":"trace"},"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"rvtrace","version":"0.1"},"io.modelcontextprotocol/clientCapabilities":{}}}}'
  echo "mcp n$n traceparent=$TP" >> "$OUT/traceparents.txt"
  TP2="00-$(openssl rand -hex 16)-$(openssl rand -hex 8)-01"
  curl -s -o /dev/null --max-time 8 -X POST "http://$GW/plain" -H 'Content-Type: application/json' \
    -H "traceparent: $TP2" -d '{"probe":"plain"}'
  echo "plain n$n traceparent=$TP2" >> "$OUT/traceparents.txt"
  sleep 2
done
sleep 8
kubectl --context $CTX -n $AGWNS logs deploy/otel-collector --since-time="$SINCE" > "$OUT/collector-spans.txt" 2>&1
note "- traceparent 원본은 \`traceparents.txt\`, 수집기 로그 원문은 \`collector-spans.txt\`."
note "- 스팬 요약(이름, trace-id, span-id, parent):"
note '```'
"$PY" - "$OUT/collector-spans.txt" "$OUT/traceparents.txt" >> "$OUT/FINDINGS.md" <<'PYEOF'
import re, sys, collections

text = open(sys.argv[1], errors="ignore").read()
sent = {}
for line in open(sys.argv[2], errors="ignore"):
    m = re.match(r"(\S+) n(\d+) traceparent=00-([0-9a-f]{32})-([0-9a-f]{16})-", line.strip())
    if m:
        sent[m.group(3)] = (m.group(1), m.group(4))     # trace -> (경로, 클라이언트 span)

spans = []
for block in re.split(r"^Span #\d+$", text, flags=re.M)[1:]:
    def g(key):
        m = re.search(rf"^\s+{re.escape(key)}\s*:\s*(\S+)\s*$", block, re.M)
        return m.group(1) if m else "-"
    spans.append(dict(trace=g("Trace ID"), parent=g("Parent ID"), sid=g("ID"),
                      name=g("Name"), kind=g("Kind")))

by = collections.defaultdict(list)
for sp in spans:
    by[sp["trace"]].append(sp)

print(f"{'경로':6s} {'trace(앞 8)':12s} {'서버 span':18s} {'서버 parent':18s} {'클라 parent':18s} 판정")
for trace, group in by.items():
    route, client_span = sent.get(trace, ("?", "?"))
    srv = next((x for x in group if x["kind"] == "Server"), None)
    cli = next((x for x in group if x["kind"] == "Client"), None)
    if not srv or not cli:
        print(f"{route:6s} {trace[:8]:12s} 스팬 부족(kind={[x['kind'] for x in group]})")
        continue
    nested = cli["parent"] == srv["sid"]
    from_client = srv["parent"] == client_span
    verdict = ("중첩" if nested else "형제") + (", 클라이언트 이어받음" if from_client else ", 클라이언트 span 불일치")
    print(f"{route:6s} {trace[:8]:12s} {srv['sid']:18s} {srv['parent']:18s} {cli['parent']:18s} {verdict}")
print(f"(스팬 {len(spans)}개, 트레이스 {len(by)}개)")
PYEOF
note '```'
note ""
note "판정: 게이트웨이가 내보내는 두 스팬(Server = 들어온 요청, Client = 백엔드로 나간 요청)에서"
note "Client의 parent가 Server의 span-id면 정상 중첩이고 클라이언트가 보낸 span-id면 형제다(#2904 계열)."
note "백엔드 MCP 서버는 계측돼 있지 않아 업스트림 자체의 SERVER 스팬은 이 측정에 없다. 그래서"
note "#2904의 증상 그대로가 아니라 게이트웨이가 내보내는 스팬의 부모 관계를 두 경로에서 비교하는 것이다."
note ""
kubectl --context $CTX -n $NS delete httproute plain-b >/dev/null 2>&1

# ── T-B. 비용 (트레이싱 끔 대 켬) ─────────────────────────────────────
cell() { # cell <name> <url> <mode> <rps> <conc>
  "$PY" "$LOADGEN" --url "$2" --dialect b --tool echo \
    --concurrency "$5" --duration "$DUR" --conn-mode "$3" --rps "$4" \
    --out "$OUT/$1.json" >/dev/null 2>&1
  "$PY" -c "
import json
d=json.load(open('$OUT/$1.json'))
err=sum(d.get('errors', {}).values())
print(f\"achieved={d['achieved_rps']:.1f} p50={d['latency_ms']['p50']:.1f} p99={d['latency_ms']['p99']:.1f} err={err}\")"
}
note "## T-B. 트레이싱 비용 (게이트웨이 경유, 정책 끔 대 켬)"
note ""
note "직접 호출은 트레이싱과 무관하므로 참고용으로 회차마다 1개만 잰다(direct=$DIRECT_IP)."
note ""
for mode in close reuse; do
  note "### $mode 모드 100rps"
  note ""
  for n in $(seq 1 "$ROUNDS"); do
    delete_tracing
    log "$mode rep$n: 트레이싱 끔"
    note "- off n$n: $(cell "tr-off-$mode-n$n" "http://$GW/b" "$mode" 100 8)"
    sleep "$COOLDOWN"
    apply_tracing
    log "$mode rep$n: 트레이싱 켬"
    note "- on  n$n: $(cell "tr-on-$mode-n$n" "http://$GW/b" "$mode" 100 8)"
    sleep "$COOLDOWN"
  done
  note ""
done
note "- 참고(직접 호출, 트레이싱 무관): $(cell "tr-direct" "http://$DIRECT_IP/mcp" close 100 8)"
note ""
note "수집기 파드 상태:"
note '```'
kubectl --context $CTX -n $AGWNS get pods -l app=otel-collector >> "$OUT/FINDINGS.md" 2>&1
note '```'
log "=== rv_trace 완료: $OUT ==="
