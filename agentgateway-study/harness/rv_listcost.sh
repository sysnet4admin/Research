#!/usr/bin/env bash
# 목록 필터링 비용 (2026-09-05): 도구 수(8/100/500) x 정책 유무 x 경로에서 tools/list의
# p50/p99를 잰다. 서버 사본 k8s/b-server-tools/server.py(B_EXTRA_TOOLS)로 도구 수를 바꾸고
# (ConfigMap 교체 + env 롤아웃), 부하는 harness/loadgen_list.py --tool list.
#   경로 3: direct(정책 없음), gw-none(게이트웨이, 정책 없음), gw-policy(게이트웨이, echo만
#   허용 -> 목록이 1개로 필터링). 회차 안 교대, {close, reuse}, 회차 RV_ROUNDS, RV_RPS(기본 20)rps conc 8.
# 종료 시 원본 ConfigMap과 env 없음으로 복원.
# 사용: ./rv_listcost.sh <PYTHON> <OUT_DIR>
set -uo pipefail
PY="$1"; OUT="$2"
CTX="aaif-benchmark"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
REPO="$(cd "$STUDY/.." && pwd)"
LOADGEN="$DIR/loadgen_list.py"
ORIG_SERVER="$REPO/mcp-migration/studies/stateless-scaleout/b-server/server.py"
TOOLS_SERVER="$STUDY/k8s/b-server-tools/server.py"
DURATION="${RV_DURATION:-30}"
CD_CLOSE="${RV_COOLDOWN_CLOSE:-180}"
CD_REUSE="${RV_COOLDOWN_REUSE:-60}"
ROUNDS="${RV_ROUNDS:-5}"
EXTRAS="${RV_EXTRAS:-0 92 492}"   # 기본 8개 + 추가 -> 총 8 / 100 / 500
RPS="${RV_RPS:-20}"   # 500개 목록은 응답당 ~100ms(서버 직렬화)라 100rps는 포화(리허설 0904). 비포화 속도로 잰다.
mkdir -p "$OUT"
log() { echo "[$(date '+%m-%d %H:%M')] $*"; }
note() { echo "$*" >> "$OUT/FINDINGS.md"; }
cooldown() { [ "$1" = close ] && sleep "$CD_CLOSE" || sleep "$CD_REUSE"; }
set_tools() {
  kubectl --context $CTX -n $NS create configmap b-server-code --from-file=server.py="$TOOLS_SERVER" \
    --dry-run=client -o yaml | kubectl --context $CTX apply -f - >/dev/null 2>&1
  kubectl --context $CTX -n $NS set env deploy/mcp-b B_EXTRA_TOOLS="$1" >/dev/null 2>&1
  kubectl --context $CTX -n $NS rollout restart deploy/mcp-b >/dev/null 2>&1
  kubectl --context $CTX -n $NS rollout status deploy/mcp-b --timeout=180s >/dev/null 2>&1 || return 1
  sleep 10
}
restore_backend() {
  kubectl --context $CTX -n $NS create configmap b-server-code --from-file=server.py="$ORIG_SERVER" \
    --dry-run=client -o yaml | kubectl --context $CTX apply -f - >/dev/null 2>&1
  kubectl --context $CTX -n $NS set env deploy/mcp-b B_EXTRA_TOOLS- >/dev/null 2>&1
  kubectl --context $CTX -n $NS rollout restart deploy/mcp-b >/dev/null 2>&1
  kubectl --context $CTX -n $NS rollout status deploy/mcp-b --timeout=180s >/dev/null 2>&1
}
policy_on() {
  cat <<YAML | kubectl --context $CTX apply -f - >/dev/null 2>&1
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata:
  name: listcost-allow-echo
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
            - mcp.tool.name == "echo"
YAML
  sleep 12
}
policy_off() { kubectl --context $CTX -n $NS delete agentgatewaypolicy listcost-allow-echo >/dev/null 2>&1; sleep 10; }
cell() { # cell <name> <url> <mode>
  "$PY" "$LOADGEN" --url "$2" --dialect b --tool list --concurrency 8 --duration "$DURATION" \
    --conn-mode "$3" --rps "$RPS" --out "$OUT/$1.json" >/dev/null 2>&1
  "$PY" -c "
import json
d=json.load(open('$OUT/$1.json'))
err=sum(d.get('errors', {}).values())
print(f\"achieved={d['achieved_rps']:.1f} p50={d['latency_ms']['p50']:.1f} p99={d['latency_ms']['p99']:.1f} err={err} shed={d.get('shed',0)} tools={d.get('tools_count')} bytes={d.get('body_bytes')}\")"
}

"$PY" -c "import httpx" 2>/dev/null || { log "[중단] venv httpx 없음"; exit 1; }
GW=$(kubectl --context $CTX -n agentgateway-system get gateway agentgateway-proxy -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
[ -z "$GW" ] && { log "[중단] 게이트웨이 주소 없음"; exit 1; }
kubectl --context $CTX -n $NS get agentgatewaypolicy -o name 2>/dev/null | grep -q . && { log "[중단] 잔여 정책 있음"; exit 1; }
DIRECT_URL="http://$(kubectl --context $CTX -n $NS get svc mcp-b -o jsonpath='{.status.loadBalancer.ingress[0].ip}')/mcp"
GW_URL="http://$GW/b"
AGWV=$(kubectl --context $CTX -n agentgateway-system get deploy agentgateway-proxy -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | sed 's/.*://')

echo "# 목록 필터링 비용: 도구 수 x 정책 유무 x 경로 (자동 생성, agentgateway $AGWV)" > "$OUT/FINDINGS.md"
note ""
note "실행 $(date '+%Y-%m-%d %H:%M'). 컨텍스트 $CTX. direct=\`$DIRECT_URL\` gw=\`$GW_URL\`. tools/list ${RPS}rps conc 8, ${DURATION}초 셀."
note "도구 수 = 8 + {${EXTRAS}}. 경로 = direct / gw-none / gw-policy(echo만 허용). 회차 ${ROUNDS}, 쿨다운 close ${CD_CLOSE}s / reuse ${CD_REUSE}s."
note "- 전원: $(pmset -g batt | head -1 | sed "s/Now drawing from //")"
note ""
for x in $EXTRAS; do
  total=$((8 + x))
  log "=== 도구 ${total}개 롤아웃 (extra $x) ==="
  set_tools "$x" || { log "[중단] 롤아웃 실패(extra $x)"; restore_backend; exit 1; }
  note "## 도구 ${total}개"
  for mode in close reuse; do
    for n in $(seq 1 "$ROUNDS"); do
      log "=== t${total} ${mode} n${n}: direct ==="
      note "  - t${total} ${mode} direct    n${n}: $(cell "list-t${total}-${mode}-direct-n${n}" "$DIRECT_URL" "$mode")"
      cooldown "$mode"
      log "=== t${total} ${mode} n${n}: gw-none ==="
      note "  - t${total} ${mode} gw-none   n${n}: $(cell "list-t${total}-${mode}-gwnone-n${n}" "$GW_URL" "$mode")"
      cooldown "$mode"
      policy_on
      log "=== t${total} ${mode} n${n}: gw-policy ==="
      note "  - t${total} ${mode} gw-policy n${n}: $(cell "list-t${total}-${mode}-gwpolicy-n${n}" "$GW_URL" "$mode")"
      policy_off
      cooldown "$mode"
    done
  done
  note ""
done
log "백엔드 원본 복원"
restore_backend
note ""
note "---"
note "종료 $(date '+%Y-%m-%d %H:%M'). 백엔드 코드와 env를 원본으로 복원했다(게이트웨이 상주, 정책 0)."
log "=== 목록 비용 완료: $OUT ==="
