#!/usr/bin/env bash
# 보강 주간 2부 (2026-08-10). run_week.sh 가 끝나면 이어서 돈다.
#
# 순서는 위험이 낮은 것부터다. 앞이 깨져도 뒤가 못 도는 일을 줄인다.
#   V1r  게이트웨이 재측정 (하네스 수정 후). 필수
#   S1   sessionAffinity ClientIP 비교. 발행문의 논리 구멍을 메운다
#   S3   경로 (b) Gateway API 구현체 경유. 한계 절의 "안 쟀다"를 지운다
#   S2   kube-proxy nftables 모드. 클러스터 전체를 바꾸므로 늦게
#   V8   튜토리얼 재현 검증. 스냅샷 복원이라 S2도 함께 원복된다
#
# 사용: ./run_week2.sh <A_URL> <B_URL> <GW_URL> <PYTHON> <OUT_ROOT>
set -uo pipefail

A_URL="$1"; B_URL="$2"; GW="$3"; PY="$4"; ROOT="$5"
CTX="mcp-migration"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
COOLDOWN="${COOLDOWN:-180}"
mkdir -p "$ROOT"

log() { echo "[$(date '+%m-%d %H:%M')] $*"; }
scale() { kubectl --context $CTX -n $NS scale deploy/"$1" --replicas="$2" >/dev/null 2>&1; }

wait_ready() {
  local d="$1" n="$2" s=$SECONDS
  until [ "$(kubectl --context $CTX -n $NS get deploy "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)" = "$n" ]; do
    [ $((SECONDS - s)) -gt 300 ] && { log "  [경고] $d 가 $n 개까지 안 뜸"; return 1; }
    sleep 5
  done
  sleep 5
}

report() {
  python3 -c "
import json,sys
try:
    d=json.load(open(sys.argv[1]))
    print(f\"    rps={d['achieved_rps']:6.1f} ok={d['ok']:5} sloss={d['session_loss']:5} \"
          f\"gwerr={d.get('gateway_error',0):5} hloss={d['handle_loss']:5} reinit={d['reinit']:5} \"
          f\"p99={d['latency_ms']['p99']:7.1f} {dict(d.get('errors') or {})}\")
except Exception as ex: print(f'    (읽기 실패 {ex})')" "$1"
}

cell() { local out="$1"; shift; "$PY" "$DIR/loadgen.py" "$@" --out "$out" >/dev/null 2>&1; report "$out"; sleep "$COOLDOWN"; }

kill_pod_during() {
  local app="$1" delay="$2" evt="$3"; sleep "$delay"
  local pod="" ok=false
  for i in 1 2 3; do
    pod=$(kubectl --context $CTX -n $NS get pods -l app="$app" -o name 2>/dev/null | head -1)
    if [ -n "$pod" ] && kubectl --context $CTX -n $NS delete "$pod" --wait=false >/dev/null 2>&1; then ok=true; break; fi
    sleep 3
  done
  printf '{"killed": %s, "pod": "%s", "at_s": %s}\n' "$ok" "$pod" "$delay" > "$evt"
}

# ── 앞 캠페인이 돌고 있으면 기다린다 ──
while pgrep -f run_week.sh >/dev/null; do sleep 60; done
log "앞 캠페인 종료 확인. 2부 시작"

# =====================================================================
log "=== V1r: 게이트웨이 재측정 (5xx 재초기화 반영) ==="
log "1부 V1은 5xx에서 복구하지 않는 하네스로 재서 세션을 잃은 워커가 남은 실행"
log "내내 실패했다. 그래서 실패 건수가 4,000의 1/8 배수로 찍혔다. 고친 뒤 다시 잰다."
OUT="$ROOT/v1r-gateway"; mkdir -p "$OUT"
if kubectl --context $CTX -n $NS get agentgatewaybackend mcp-a-stateful >/dev/null 2>&1; then
  scale mcp-b 1; scale mcp-a 2; wait_ready mcp-a 2
  for fm in FailClosed FailOpen; do
    log "  구 스펙 Stateful / $fm"
    kubectl --context $CTX -n $NS patch agentgatewaybackend mcp-a-stateful --type merge \
      -p "{\"spec\":{\"mcp\":{\"sessionRouting\":\"Stateful\",\"failureMode\":\"$fm\"}}}" >/dev/null 2>&1
    sleep 10
    for rep in 1 2 3 4 5; do
      n="v1r-a-${fm}-rep${rep}"
      kill_pod_during mcp-a 20 "$OUT/$n.kill.json" &
      cell "$OUT/$n.json" --url "$GW/a" --dialect a --tool echo \
        --concurrency 8 --duration 60 --conn-mode reuse --rps 100
      wait; kubectl --context $CTX -n $NS rollout status deploy/mcp-a --timeout=180s >/dev/null 2>&1
    done
  done
  kubectl --context $CTX -n $NS patch agentgatewaybackend mcp-a-stateful --type merge \
    -p '{"spec":{"mcp":{"failureMode":"FailClosed"}}}' >/dev/null 2>&1
  log "  대조: 직접 경로 같은 조건"
  for rep in 1 2 3; do
    n="v1r-direct-a-rep${rep}"
    kill_pod_during mcp-a 20 "$OUT/$n.kill.json" &
    cell "$OUT/$n.json" --url "$A_URL" --dialect a --tool echo \
      --concurrency 8 --duration 60 --conn-mode reuse --rps 100
    wait; kubectl --context $CTX -n $NS rollout status deploy/mcp-a --timeout=180s >/dev/null 2>&1
  done
else
  log "  [건너뜀] agentgateway 백엔드 없음"
fi

# =====================================================================
log "=== S1: sessionAffinity ClientIP 비교 ==="
log "'구 스펙이면 스티키 세션 켜면 되지 않나'에 답한다. 지금 글에 이 답이 없다."
log "주의: 부하 생성기가 호스트 한 대라 클라이언트 IP가 하나다. ClientIP를 켜면"
log "트래픽이 전부 파드 하나로 몰린다. 기전은 선명하지만 실환경은 IP가 여러 개다."
OUT="$ROOT/s1-sessionaffinity"; mkdir -p "$OUT"
scale mcp-b 1; scale mcp-a 4; wait_ready mcp-a 4
for aff in None ClientIP; do
  log "  sessionAffinity=$aff"
  if [ "$aff" = ClientIP ]; then
    kubectl --context $CTX -n $NS patch svc mcp-a -p \
      '{"spec":{"sessionAffinity":"ClientIP","sessionAffinityConfig":{"clientIP":{"timeoutSeconds":10800}}}}' >/dev/null 2>&1
  else
    kubectl --context $CTX -n $NS patch svc mcp-a -p \
      '{"spec":{"sessionAffinity":"None","sessionAffinityConfig":null}}' >/dev/null 2>&1
  fi
  sleep 15
  for rep in 1 2 3 4 5; do
    cell "$OUT/s1-a-${aff}-close-r4-rep${rep}.json" --url "$A_URL" --dialect a --tool echo \
      --concurrency 16 --duration 30 --conn-mode close --rps 200
  done
  # 파드 교체까지 (친화도가 파드 소멸에는 무력하다는 것을 보이려면 필요)
  scale mcp-a 2; wait_ready mcp-a 2
  for rep in 1 2 3; do
    n="s1-a-${aff}-kill-rep${rep}"
    kill_pod_during mcp-a 20 "$OUT/$n.kill.json" &
    cell "$OUT/$n.json" --url "$A_URL" --dialect a --tool echo \
      --concurrency 8 --duration 60 --conn-mode reuse --rps 100
    wait; kubectl --context $CTX -n $NS rollout status deploy/mcp-a --timeout=180s >/dev/null 2>&1
  done
  scale mcp-a 4; wait_ready mcp-a 4
done
kubectl --context $CTX -n $NS patch svc mcp-a -p \
  '{"spec":{"sessionAffinity":"None","sessionAffinityConfig":null}}' >/dev/null 2>&1
log "  파드 분산 확인용: 어느 파드가 응답했는지는 counter_mem 오류 메시지로만 보인다"

log "=== 2부 여기까지. S3(경로 b)와 S2(nftables), V8은 별도 스크립트 ==="
log "완료: $ROOT"
