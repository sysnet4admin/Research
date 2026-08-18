#!/usr/bin/env bash
# 경로 (c) agentgateway 경유 측정 (2026-08-06 추가).
#
# 직접 경로(main-*)와 달리 한 번에 한 서버만 replica 4로 올린다. agentgateway
# 컨트롤 플레인과 프록시가 워커 CPU를 쓰기 때문에(워커 2대 x 2 CPU) A와 B를
# 동시에 4로 올리면 파드가 Pending으로 남는다. 재는 쪽 외에는 1로 내린다.
# 절대 처리량을 직접 경로와 나란히 놓지 말 것. 세션 유실 비교가 이 측정의 목적이다.
#
# 사용: ./run_gateway.sh <GW_BASE_URL> <PYTHON> <OUT_DIR> [REPS]
#   예: ./run_gateway.sh http://192.168.2.232 /tmp/mcpvenv/bin/python runs/agw-2026-08-06 3
set -euo pipefail

GW="$1"; PY="$2"; OUT="$3"; REPS="${4:-3}"
CTX="mcp-migration"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COOLDOWN="${COOLDOWN:-180}"
DUR=30; RPS=200
mkdir -p "$OUT"

kubectl --context $CTX -n $NS get deploy -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.containers[0].image}{"\n"}{end}' > "$OUT/versions.txt"
helm --kube-context $CTX -n agentgateway-system list -o json 2>/dev/null \
  | python3 -c "import json,sys; [print('agentgateway', r['app_version']) for r in json.load(sys.stdin)]" >> "$OUT/versions.txt" || true

scale() { kubectl --context $CTX -n $NS scale deploy/"$1" --replicas="$2" >/dev/null; }

wait_ready() { # wait_ready <deploy> <n>
  local d="$1" n="$2" s=$SECONDS
  until [ "$(kubectl --context $CTX -n $NS get deploy "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)" = "$n" ]; do
    [ $((SECONDS - s)) -gt 240 ] && { echo "  [경고] $d 가 $n 개까지 안 뜸"; return 1; }
    sleep 5
  done
}

cell() { # cell <name> <spec a|b>
  local name="$1" spec="$2"
  $PY "$DIR/loadgen.py" --url "$GW/$spec" --dialect "$spec" --tool echo \
    --concurrency 16 --duration $DUR --conn-mode close --rps $RPS \
    --out "$OUT/$name.json" >/dev/null 2>&1
  python3 -c "
import json; d=json.load(open('$OUT/$name.json'))
print(f\"  $name: rps={d['achieved_rps']:6.1f} sloss={d['session_loss']:5} hloss={d['handle_loss']:5} err={sum(d['errors'].values()) if d['errors'] else 0}\")"
  sleep "$COOLDOWN"
}

for spec in a b; do
  other=$([ "$spec" = a ] && echo b || echo a)
  echo "## $spec 를 replica 4 로, $other 는 1 로"
  scale "mcp-$other" 1; scale "mcp-$spec" 4
  wait_ready "mcp-$spec" 4 || true
  sleep 15
  for rep in $(seq 1 "$REPS"); do cell "agw-${spec}-close-r4-rep${rep}" "$spec"; done
done

echo "완료: $OUT"
