#!/usr/bin/env bash
# 혼합 백엔드(head-of-line) 보강 (2026-09-04): 같은 게이트웨이 뒤에 빠른 백엔드(mcp-b,
# 0ms)와 느린 백엔드(mcp-b-slow, 200ms)를 두고, 느린 쪽에 부하가 걸릴 때 빠른 쪽의
# p50/p99가 달라지는지 잰다. 직접 경로에서도 같은 혼합을 걸어 호스트 경합을 분리한다.
#   축 1. 4셀 교대 x {close, reuse} x 회차 RV_ROUNDS: gw-alone, gw-mixed, direct-alone,
#         direct-mixed (짝수 회차는 역순). 측정값은 빠른 쪽(100rps, conc 8)이고
#         혼합 셀은 느린 쪽에 100rps(conc 40) 부하를 같은 경로로 동시에 건다.
#   축 2. 지속 창: gw-alone 대 gw-mixed, RV_SUSTAIN초 x {close, reuse}.
# 사용: ./rv_mixed.sh <PYTHON> <OUT_DIR>
set -uo pipefail

PY="$1"; OUT="$2"
CTX="aaif-benchmark"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
REPO="$(cd "$STUDY/.." && pwd)"
LOADGEN="$REPO/mcp-migration/studies/stateless-scaleout/harness/loadgen.py"
DELAY_SERVER="$STUDY/k8s/b-server-delay/server.py"
DURATION="${RV_DURATION:-30}"
CD_CLOSE="${RV_COOLDOWN_CLOSE:-180}"
CD_REUSE="${RV_COOLDOWN_REUSE:-60}"
ROUNDS="${RV_ROUNDS:-5}"
SUSTAIN="${RV_SUSTAIN:-1800}"
RPS=100
mkdir -p "$OUT"
log() { echo "[$(date '+%m-%d %H:%M')] $*"; }
note() { echo "$*" >> "$OUT/FINDINGS.md"; }
cooldown() { [ "$1" = close ] && sleep "$CD_CLOSE" || sleep "$CD_REUSE"; }

"$PY" -c "import httpx" 2>/dev/null || { log "[중단] venv httpx 없음"; exit 1; }
GW=$(kubectl --context $CTX -n agentgateway-system get gateway agentgateway-proxy -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
[ -z "$GW" ] && { log "[중단] 게이트웨이 주소 없음"; exit 1; }
kubectl --context $CTX -n $NS get agentgatewaypolicy -o name 2>/dev/null | grep -q . && { log "[중단] 잔여 정책 있음"; exit 1; }
AGWV=$(kubectl --context $CTX -n agentgateway-system get deploy agentgateway-proxy -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | sed 's/.*://')

log "느린 백엔드 배포 (mcp-b-slow, 200ms)"
kubectl --context $CTX -n $NS create configmap b-server-code-slow --from-file=server.py="$DELAY_SERVER" \
  --dry-run=client -o yaml | kubectl --context $CTX apply -f - > "$OUT/install.log" 2>&1
kubectl --context $CTX apply -f "$STUDY/k8s/mixed/mcp-b-slow.yaml" >> "$OUT/install.log" 2>&1
kubectl --context $CTX -n $NS rollout status deploy/mcp-b-slow --timeout=300s >> "$OUT/install.log" 2>&1 \
  || { log "[중단] mcp-b-slow 기동 실패"; exit 1; }
sleep 15
FAST_DIRECT="http://$(kubectl --context $CTX -n $NS get svc mcp-b -o jsonpath='{.status.loadBalancer.ingress[0].ip}')/mcp"
SLOW_DIRECT="http://$(kubectl --context $CTX -n $NS get svc mcp-b-slow -o jsonpath='{.status.loadBalancer.ingress[0].ip}')/mcp"
FAST_GW="http://$GW/b"; SLOW_GW="http://$GW/bslow"
for u in "$FAST_GW" "$SLOW_GW" "$FAST_DIRECT" "$SLOW_DIRECT"; do
  code=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" -X POST "$u" \
    -H 'Accept: application/json, text/event-stream' -H 'Content-Type: application/json' \
    -H 'MCP-Protocol-Version: 2026-07-28' -H 'Mcp-Method: tools/call' -H 'Mcp-Name: echo' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo","arguments":{"message":"s"},"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"pf","version":"0.1"},"io.modelcontextprotocol/clientCapabilities":{}}}}')
  [ "$code" = "200" ] || { log "[중단] 스모크 실패 $u (HTTP $code)"; exit 1; }
done
log "스모크 4경로 200. fast gw=$FAST_GW slow gw=$SLOW_GW"

echo "# 혼합 백엔드 보강: 느린 백엔드 부하가 빠른 백엔드 꼬리에 주는 영향 (자동 생성, agentgateway $AGWV)" > "$OUT/FINDINGS.md"
note ""
note "실행 $(date '+%Y-%m-%d %H:%M'). 컨텍스트 $CTX. fast=mcp-b(0ms) slow=mcp-b-slow(200ms)."
note "fast direct=\`$FAST_DIRECT\` gw=\`$FAST_GW\` / slow direct=\`$SLOW_DIRECT\` gw=\`$SLOW_GW\`."
note "측정 경로 = fast ${RPS}rps conc 8. mixed 셀은 slow에 ${RPS}rps conc 40 부하를 같은 경로로 동시에 건다(3초 먼저 시작, ${DURATION}+6초)."
note "축 1: 4셀 교대 x {close, reuse} x 회차 ${ROUNDS}, ${DURATION}초 셀. 축 2: ${SUSTAIN}초 지속 x {close, reuse}, gw-alone 대 gw-mixed."
note "- 전원: $(pmset -g batt | head -1 | sed "s/Now drawing from //")"
note ""

summ() { "$PY" -c "
import json,sys
d=json.load(open('$1'))
err=sum(d.get('errors', {}).values())
print(f\"achieved={d['achieved_rps']:.1f} p50={d['latency_ms']['p50']:.1f} p99={d['latency_ms']['p99']:.1f} err={err} shed={d.get('shed',0)}\")"; }
cell() { # cell <name> <fast_url> <slow_url|-> <mode> <duration>
  local name="$1" furl="$2" surl="$3" mode="$4" dur="$5" spid=""
  if [ "$surl" != "-" ]; then
    "$PY" "$LOADGEN" --url "$surl" --dialect b --tool echo --concurrency 40 --duration $((dur+6)) \
      --conn-mode "$mode" --rps "$RPS" --out "$OUT/$name-slowload.json" >/dev/null 2>&1 &
    spid=$!; sleep 3
  fi
  "$PY" "$LOADGEN" --url "$furl" --dialect b --tool echo --concurrency 8 --duration "$dur" \
    --conn-mode "$mode" --rps "$RPS" --out "$OUT/$name.json" >/dev/null 2>&1
  local r; r=$(summ "$OUT/$name.json")
  if [ -n "$spid" ]; then wait "$spid"; r="$r | slow: $(summ "$OUT/$name-slowload.json")"; fi
  echo "$r"
}

note "## 축 1. 4셀 교대 (기록 순서 그대로)"
note ""
for mode in close reuse; do
  for n in $(seq 1 "$ROUNDS"); do
    if [ $((n % 2)) -eq 1 ]; then order="gw-alone gw-mixed direct-alone direct-mixed"; else order="direct-mixed direct-alone gw-mixed gw-alone"; fi
    for c in $order; do
      case "$c" in
        gw-alone)     furl="$FAST_GW"; surl="-";;
        gw-mixed)     furl="$FAST_GW"; surl="$SLOW_GW";;
        direct-alone) furl="$FAST_DIRECT"; surl="-";;
        direct-mixed) furl="$FAST_DIRECT"; surl="$SLOW_DIRECT";;
      esac
      log "=== ${mode} n${n}: ${c} ==="
      R=$(cell "mixed-${mode}-${c}-n${n}" "$furl" "$surl" "$mode" "$DURATION")
      note "  - ${mode} ${c} n${n}: $R"
      cooldown "$mode"
    done
  done
  note ""
done

note "## 축 2. 지속 창 ${SUSTAIN}초, gw-alone 대 gw-mixed"
note ""
for mode in close reuse; do
  for c in gw-alone gw-mixed; do
    surl="-"; [ "$c" = gw-mixed ] && surl="$SLOW_GW"
    log "=== 지속 ${mode}: ${c} (${SUSTAIN}s) ==="
    R=$(cell "sustain-${mode}-${c}" "$FAST_GW" "$surl" "$mode" "$SUSTAIN")
    note "  - sustain ${mode} ${c}: $R"
    cooldown "$mode"
  done
done

log "정리: mcp-b-slow 제거"
kubectl --context $CTX delete -f "$STUDY/k8s/mixed/mcp-b-slow.yaml" >> "$OUT/install.log" 2>&1
kubectl --context $CTX -n $NS delete configmap b-server-code-slow >> "$OUT/install.log" 2>&1
note ""
note "---"
note "종료 $(date '+%Y-%m-%d %H:%M'). 느린 백엔드와 라우트를 제거했다(게이트웨이와 mcp-b 상주)."
log "=== 혼합 백엔드 보강 완료: $OUT ==="
