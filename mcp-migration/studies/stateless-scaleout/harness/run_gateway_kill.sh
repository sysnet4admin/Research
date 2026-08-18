#!/usr/bin/env bash
# W5: 게이트웨이 경유에서 파드 교체 (2026-08-08 추가).
#
# 본측정은 게이트웨이 경유를 스케일아웃에서만 쟀다. 그런데 게이트웨이가 세션을
# 붙들고 있으면 그 세션이 가리키던 파드가 사라졌을 때 무슨 일이 나는지가 남는다.
# "게이트웨이는 문제를 없애는 게 아니라 옮긴다"는 해석이 맞다면 여기서 유실이
# 다시 나와야 한다. 직접 경로 M3와 같은 조건(60초, t=20s kill, 100rps)으로 잰다.
#
# 사전: k8s/agentgateway/install.sh 로 게이트웨이가 설치돼 있어야 한다.
# 사용: ./run_gateway_kill.sh <GW_BASE_URL> <PYTHON> <OUT_DIR> [REPS]
set -euo pipefail

GW="$1"; PY="$2"; OUT="$3"; REPS="${4:-3}"
CTX="mcp-migration"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COOLDOWN="${COOLDOWN:-180}"
mkdir -p "$OUT"

helm --kube-context $CTX -n agentgateway-system list -o json 2>/dev/null \
  | python3 -c "import json,sys; [print('agentgateway', r['app_version']) for r in json.load(sys.stdin)]" > "$OUT/versions.txt" || true

kill_pod_during() { # <app> <delay> <event-file>
  local app="$1" delay="$2" evt="$3"
  sleep "$delay"
  local pod="" ok=false
  for i in 1 2 3; do
    pod=$(kubectl --context $CTX -n $NS get pods -l app="$app" -o name | head -1)
    if [ -n "$pod" ] && kubectl --context $CTX -n $NS delete "$pod" --wait=false >/dev/null; then ok=true; break; fi
    sleep 3
  done
  printf '{"killed": %s, "pod": "%s", "at_s": %s}\n' "$ok" "$pod" "$delay" > "$evt"
  echo "  kill: pod=$pod ok=$ok"
}

cell() { # cell <name> <spec a|b> <tool> <conn-mode>
  local name="$1" spec="$2" tool="$3" mode="$4"
  $PY "$DIR/loadgen.py" --url "$GW/$spec" --dialect "$spec" --tool "$tool" \
    --concurrency 8 --duration 60 --conn-mode "$mode" --rps 100 \
    --out "$OUT/$name.json" >/dev/null 2>&1 || true
  python3 -c "
import json
try:
    d=json.load(open('$OUT/$name.json'))
    print(f\"  $name: rps={d['achieved_rps']:6.1f} p99={d['latency_ms']['p99']:7.1f} sloss={d['session_loss']:5} hloss={d['handle_loss']:5}\")
except Exception as e:
    print(f'  $name: 읽기 실패 {e}')"
}

# 자원 제약: 게이트웨이가 워커 CPU를 쓰므로 재는 쪽만 2로 두고 반대편은 1로 내린다
echo "## A 구 스펙 (Stateful 라우팅) 파드 교체"
kubectl --context $CTX -n $NS scale deploy/mcp-b --replicas=1 >/dev/null
kubectl --context $CTX -n $NS scale deploy/mcp-a --replicas=2 >/dev/null
kubectl --context $CTX -n $NS rollout status deploy/mcp-a --timeout=300s
sleep 10
for rep in $(seq 1 "$REPS"); do
  kill_pod_during mcp-a 20 "$OUT/w5-agw-a-kill-rep${rep}.kill.json" &
  cell "w5-agw-a-kill-rep${rep}" a echo reuse
  wait; kubectl --context $CTX -n $NS rollout status deploy/mcp-a --timeout=180s; sleep "$COOLDOWN"
done

echo "## B 신 스펙 (Stateless 라우팅) 파드 교체"
kubectl --context $CTX -n $NS scale deploy/mcp-a --replicas=1 >/dev/null
kubectl --context $CTX -n $NS scale deploy/mcp-b --replicas=2 >/dev/null
kubectl --context $CTX -n $NS rollout status deploy/mcp-b --timeout=300s
sleep 10
for rep in $(seq 1 "$REPS"); do
  kill_pod_during mcp-b 20 "$OUT/w5-agw-b-kill-rep${rep}.kill.json" &
  cell "w5-agw-b-kill-rep${rep}" b counter_hmac close
  wait; kubectl --context $CTX -n $NS rollout status deploy/mcp-b --timeout=180s; sleep "$COOLDOWN"
done

echo "완료: $OUT"
