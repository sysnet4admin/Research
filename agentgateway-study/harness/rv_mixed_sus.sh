#!/usr/bin/env bash
# 혼합 백엔드 30분 close 창의 귀속 보강 (2026-09-05): 체인7에서 게이트웨이 경로의 close 혼합
# 30분 창이 두 팔 모두 shed를 냈다(빠른 팔 22%, 느린 팔 15%, 게이트웨이 오류 0). 같은 조건을
# 직접 경로(둘 다 LB 직접)에서 재고, 게이트웨이 경로를 한 번 더 재서 병목이 게이트웨이인지
# 호스트/노드(연결 수립률)인지 가른다. rv_mixed.sh의 최소 델타 사본(축 2만, 팔 선택).
# 사용: RV_SUS_ARMS="direct gw" ./rv_mixed_sus.sh <PYTHON> <OUT_DIR>
set -uo pipefail
PY="$1"; OUT="$2"
CTX="aaif-benchmark"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
REPO="$(cd "$STUDY/.." && pwd)"
LOADGEN="$REPO/mcp-migration/studies/stateless-scaleout/harness/loadgen.py"
DELAY_SERVER="$STUDY/k8s/b-server-delay/server.py"
SUSTAIN="${RV_SUSTAIN:-1800}"
CD="${RV_COOLDOWN:-180}"
ARMS="${RV_SUS_ARMS:-direct gw}"
MODES="${RV_SUS_MODES:-close}"
RPS=100
mkdir -p "$OUT"
log() { echo "[$(date '+%m-%d %H:%M')] $*"; }
note() { echo "$*" >> "$OUT/FINDINGS.md"; }

"$PY" -c "import httpx" 2>/dev/null || { log "[중단] venv httpx 없음"; exit 1; }
GW=$(kubectl --context $CTX -n agentgateway-system get gateway agentgateway-proxy -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
[ -z "$GW" ] && { log "[중단] 게이트웨이 주소 없음"; exit 1; }
kubectl --context $CTX -n $NS get agentgatewaypolicy -o name 2>/dev/null | grep -q . && { log "[중단] 잔여 정책 있음"; exit 1; }
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

summ() { "$PY" -c "
import json
d=json.load(open('$1'))
err=sum(d.get('errors', {}).values())
print(f\"achieved={d['achieved_rps']:.1f} p50={d['latency_ms']['p50']:.1f} p99={d['latency_ms']['p99']:.1f} err={err} shed={d.get('shed',0)} ok={d['ok']}\")"; }
cell() { # cell <name> <fast_url> <slow_url> <mode> <duration>
  local name="$1" furl="$2" surl="$3" mode="$4" dur="$5"
  "$PY" "$LOADGEN" --url "$surl" --dialect b --tool echo --concurrency 40 --duration $((dur+6)) \
    --conn-mode "$mode" --rps "$RPS" --out "$OUT/$name-slowload.json" >/dev/null 2>&1 &
  local spid=$!; sleep 3
  "$PY" "$LOADGEN" --url "$furl" --dialect b --tool echo --concurrency 8 --duration "$dur" \
    --conn-mode "$mode" --rps "$RPS" --out "$OUT/$name.json" >/dev/null 2>&1
  local r; r=$(summ "$OUT/$name.json"); wait "$spid"
  echo "$r | slow: $(summ "$OUT/$name-slowload.json")"
}

echo "# 혼합 백엔드 지속 창 귀속 보강 (자동 생성)" > "$OUT/FINDINGS.md"
note ""
note "실행 $(date '+%Y-%m-%d %H:%M'). ${SUSTAIN}초 혼합 창(fast ${RPS}rps conc 8 + slow ${RPS}rps conc 40), 팔 {${ARMS}} x 모드 {${MODES}}, 셀 간 ${CD}초."
note "direct 팔은 두 부하 모두 LB 직접, gw 팔은 두 부하 모두 게이트웨이 경유."
note "- 전원: $(pmset -g batt | head -1 | sed "s/Now drawing from //")"
note ""
for mode in $MODES; do
  for arm in $ARMS; do
    if [ "$arm" = gw ]; then furl="$FAST_GW"; surl="$SLOW_GW"; else furl="$FAST_DIRECT"; surl="$SLOW_DIRECT"; fi
    log "=== 지속 ${mode} ${arm}-mixed (${SUSTAIN}s) ==="
    R=$(cell "sustain-${mode}-${arm}-mixed" "$furl" "$surl" "$mode" "$SUSTAIN")
    note "  - sustain ${mode} ${arm}-mixed: $R"
    sleep "$CD"
  done
done
log "정리: mcp-b-slow 제거"
kubectl --context $CTX delete -f "$STUDY/k8s/mixed/mcp-b-slow.yaml" >> "$OUT/install.log" 2>&1
kubectl --context $CTX -n $NS delete configmap b-server-code-slow >> "$OUT/install.log" 2>&1
note ""
note "---"
note "종료 $(date '+%Y-%m-%d %H:%M'). 느린 백엔드 제거."
log "=== 완료: $OUT ==="
