#!/usr/bin/env bash
# 보강 주간 캠페인 (2026-08-10 착수). 계획과 근거는 WEEK.md 참조.
#
# 일주일 무인 실행이라 두 가지를 지킨다.
#   1. 단계는 서로 독립이다. 앞 단계가 실패해도 뒤가 돌아간다
#   2. 무엇을 언제 했는지 로그에 남긴다. 중간에 죽어도 어디까지 됐는지 보인다
#
# V8(튜토리얼 재현 검증)은 클러스터를 갈아엎으므로 여기 넣지 않는다. 별도로 돌린다.
#
# 사용: ./run_week.sh <A_URL> <B_URL> <GW_URL> <PYTHON> <OUT_ROOT>
set -uo pipefail   # -e 는 쓰지 않는다. 한 셀 실패가 전체를 죽이면 안 된다

A_URL="$1"; B_URL="$2"; GW="$3"; PY="$4"; ROOT="$5"
CTX="mcp-migration"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COOLDOWN="${COOLDOWN:-180}"
mkdir -p "$ROOT"

log() { echo "[$(date '+%m-%d %H:%M')] $*"; }

scale() { kubectl --context $CTX -n $NS scale deploy/"$1" --replicas="$2" >/dev/null 2>&1; }

wait_ready() { # <deploy> <n>
  local d="$1" n="$2" s=$SECONDS
  until [ "$(kubectl --context $CTX -n $NS get deploy "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)" = "$n" ]; do
    [ $((SECONDS - s)) -gt 300 ] && { log "  [경고] $d 가 $n 개까지 안 뜸"; return 1; }
    sleep 5
  done
  sleep 5
}

report() { # <json path>
  python3 -c "
import json,sys
try:
    d=json.load(open(sys.argv[1]))
    e=d.get('errors') or {}
    print(f\"    rps={d['achieved_rps']:6.1f} ok={d['ok']:5} sloss={d['session_loss']:5} \"
          f\"gwerr={d.get('gateway_error',0):5} hloss={d['handle_loss']:5} p99={d['latency_ms']['p99']:7.1f} {dict(e)}\")
except Exception as ex:
    print(f'    (읽기 실패 {ex})')" "$1"
}

cell() { # cell <out_json> <loadgen args...>
  local out="$1"; shift
  "$PY" "$DIR/loadgen.py" "$@" --out "$out" >/dev/null 2>&1
  report "$out"
  sleep "$COOLDOWN"
}

kill_pod_during() { # <app> <delay> <event-file>
  local app="$1" delay="$2" evt="$3"
  sleep "$delay"
  local pod="" ok=false
  for i in 1 2 3; do
    pod=$(kubectl --context $CTX -n $NS get pods -l app="$app" -o name 2>/dev/null | head -1)
    if [ -n "$pod" ] && kubectl --context $CTX -n $NS delete "$pod" --wait=false >/dev/null 2>&1; then ok=true; break; fi
    sleep 3
  done
  printf '{"killed": %s, "pod": "%s", "at_s": %s}\n' "$ok" "$pod" "$delay" > "$evt"
}

set_backend() { # <name> <sessionRouting> <failureMode|->
  local name="$1" sr="$2" fm="$3"
  local patch="{\"spec\":{\"mcp\":{\"sessionRouting\":\"$sr\""
  [ "$fm" != "-" ] && patch="$patch,\"failureMode\":\"$fm\""
  patch="$patch}}}"
  kubectl --context $CTX -n $NS patch agentgatewaybackend "$name" --type merge -p "$patch" >/dev/null 2>&1
  sleep 10   # 컨트롤 플레인이 반영할 시간
}

# =====================================================================
log "=== V1: 게이트웨이 failureMode 검증 ==="
log "W5의 500 3,540건이 설정 탓인지 구조 탓인지 가른다. FailClosed가 기본값이고"
log "'대상이 사라지면 세션 전체를 실패'시킨다. FailOpen은 살아있는 대상으로 계속 서빙."
OUT="$ROOT/v1-gateway-failuremode"; mkdir -p "$OUT"
if kubectl --context $CTX -n $NS get agentgatewaybackend mcp-a-stateful >/dev/null 2>&1; then
  scale mcp-b 1; scale mcp-a 2; wait_ready mcp-a 2
  for combo in "Stateful FailClosed" "Stateful FailOpen" "Stateless -"; do
    set -- $combo; sr="$1"; fm="$2"
    log "  구 스펙: sessionRouting=$sr failureMode=$fm"
    set_backend mcp-a-stateful "$sr" "$fm"
    for rep in 1 2 3 4 5; do
      n="v1-a-${sr}-${fm}-rep${rep}"
      kill_pod_during mcp-a 20 "$OUT/$n.kill.json" &
      cell "$OUT/$n.json" --url "$GW/a" --dialect a --tool echo \
        --concurrency 8 --duration 60 --conn-mode reuse --rps 100
      wait
      kubectl --context $CTX -n $NS rollout status deploy/mcp-a --timeout=180s >/dev/null 2>&1
    done
  done
  set_backend mcp-a-stateful Stateful FailClosed   # 원복

  scale mcp-a 1; scale mcp-b 2; wait_ready mcp-b 2
  for fm in FailClosed FailOpen; do
    log "  신 스펙: sessionRouting=Stateless failureMode=$fm"
    set_backend mcp-b-stateless Stateless "$fm"
    for rep in 1 2 3; do
      n="v1-b-Stateless-${fm}-rep${rep}"
      kill_pod_during mcp-b 20 "$OUT/$n.kill.json" &
      cell "$OUT/$n.json" --url "$GW/b" --dialect b --tool counter_hmac \
        --concurrency 8 --duration 60 --conn-mode close --rps 100
      wait
      kubectl --context $CTX -n $NS rollout status deploy/mcp-b --timeout=180s >/dev/null 2>&1
    done
  done
  set_backend mcp-b-stateless Stateless FailClosed
else
  log "  [건너뜀] agentgateway 백엔드가 없다"
fi

# =====================================================================
log "=== V3: M1 전 셀 고반복 (12셀 x 10회) ==="
log "표의 모든 값을 3회 중앙값에서 분포로 바꾼다."
OUT="$ROOT/v3-highrep"; mkdir -p "$OUT"
for spec in a b; do
  other=$([ "$spec" = a ] && echo b || echo a)
  url=$([ "$spec" = a ] && echo "$A_URL" || echo "$B_URL")
  scale "mcp-$other" 1
  for r in 1 2 4; do
    scale "mcp-$spec" $r; wait_ready "mcp-$spec" $r
    for mode in close reuse; do
      log "  $spec / replica $r / $mode"
      for rep in $(seq 1 10); do
        cell "$OUT/v3-${spec}-${mode}-r${r}-rep${rep}.json" --url "$url" --dialect "$spec" \
          --tool echo --concurrency 16 --duration 30 --conn-mode "$mode" --rps 200
      done
    done
  done
done

# =====================================================================
log "=== V4: 핸들 설계 x 파드 교체 ==="
log "M3는 구 스펙 echo와 신 스펙 HMAC만 쟀다. 파드 메모리 핸들은 파드가 죽으면"
log "그 상태가 전부 사라지는 가장 극적인 경우인데 재지 않았다."
OUT="$ROOT/v4-handle-kill"; mkdir -p "$OUT"
scale mcp-a 1; scale mcp-b 2; wait_ready mcp-b 2
for tool in counter_mem counter_hmac counter_redis; do
  log "  $tool"
  for rep in 1 2 3 4 5; do
    n="v4-${tool}-rep${rep}"
    kill_pod_during mcp-b 20 "$OUT/$n.kill.json" &
    cell "$OUT/$n.json" --url "$B_URL" --dialect b --tool "$tool" \
      --concurrency 8 --duration 60 --conn-mode close --rps 100
    wait
    kubectl --context $CTX -n $NS rollout status deploy/mcp-b --timeout=180s >/dev/null 2>&1
  done
done

# =====================================================================
log "=== V5: Redis 의존성 장애 ==="
log "'Redis에 두면 된다'의 정직한 반대편. 외부 저장은 새 의존성을 들이는 선택이다."
OUT="$ROOT/v5-redis-down"; mkdir -p "$OUT"
for rep in 1 2 3; do
  ( sleep 20
    kubectl --context $CTX -n $NS delete pod -l app=redis --wait=false >/dev/null 2>&1
    echo '{"killed": true, "target": "redis", "at_s": 20}' > "$OUT/v5-redis-kill-rep${rep}.kill.json" ) &
  cell "$OUT/v5-redis-kill-rep${rep}.json" --url "$B_URL" --dialect b --tool counter_redis \
    --concurrency 8 --duration 60 --conn-mode close --rps 100
  wait
  kubectl --context $CTX -n $NS rollout status deploy/redis --timeout=180s >/dev/null 2>&1
  sleep 20
done
log "  대조: Redis 정상일 때"
for rep in 1 2 3; do
  cell "$OUT/v5-redis-ok-rep${rep}.json" --url "$B_URL" --dialect b --tool counter_redis \
    --concurrency 8 --duration 60 --conn-mode close --rps 100
done

# =====================================================================
log "=== V6: 레플리카 6 확인점 ==="
log "1, 2, 4의 추세가 이어지는지, 유실률이 이론값 (N-1)/N에 계속 맞는지."
OUT="$ROOT/v6-replica6"; mkdir -p "$OUT"
scale mcp-b 1
if scale mcp-a 6 && wait_ready mcp-a 6; then
  for rep in 1 2 3 4 5; do
    cell "$OUT/v6-a-close-r6-rep${rep}.json" --url "$A_URL" --dialect a --tool echo \
      --concurrency 16 --duration 30 --conn-mode close --rps 200
  done
  "$PY" "$DIR/probe_onset.py" "$A_URL" 60 "$OUT/v6-onset-r6.json" 2>&1 | tail -3
else
  log "  [건너뜀] 레플리카 6이 안 뜬다 (워커 CPU 부족)"
fi
scale mcp-a 2

# =====================================================================
log "=== V7: 장시간 안정성 (30분) ==="
log "지금 측정은 전부 30초와 60초라 드리프트를 볼 수 없었다."
OUT="$ROOT/v7-long"; mkdir -p "$OUT"
scale mcp-a 1; scale mcp-b 4; wait_ready mcp-b 4
cell "$OUT/v7-b-close-r4-30min.json" --url "$B_URL" --dialect b --tool echo \
  --concurrency 16 --duration 1800 --conn-mode close --rps 200
scale mcp-b 1; scale mcp-a 4; wait_ready mcp-a 4
cell "$OUT/v7-a-reuse-r4-30min.json" --url "$A_URL" --dialect a --tool echo \
  --concurrency 16 --duration 1800 --conn-mode reuse --rps 200

log "=== 전체 완료: $ROOT ==="
