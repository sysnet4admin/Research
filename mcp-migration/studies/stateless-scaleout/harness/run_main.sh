#!/usr/bin/env bash
# 본측정 러너 (7/28 스펙 확정판 + SDK 안정판 전제).
# 파일럿과의 차이: 열린 루프(--rps), replica 1/2/4 스케일아웃 곡선, 반복 3회,
# kill 이벤트 기록, 전 회차 버전 스탬프.
#
# 사용: ./run_main.sh <A_URL> <B_URL> <PYTHON> <OUT_DIR> [REPS]
# 수치는 이 러너로 뜬 것만 발행 대상 (파일럿 수치는 Internal).
set -euo pipefail

A_URL="$1"; B_URL="$2"; PY="$3"; OUT="$4"; REPS="${5:-3}"
CTX="mcp-migration"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LG="$PY $DIR/loadgen.py"
DUR=30
RPS=200   # 열린 루프 목표. 파일럿 관측(close 최고 387rps)의 절반 수준 = 비포화 영역
mkdir -p "$OUT"

# 버전 스탬프 (발행 시 필수)
kubectl --context $CTX -n $NS get deploy -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.containers[0].image}{"\n"}{end}' > "$OUT/versions.txt"
kubectl --context $CTX version -o json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print('k8s', d.get('serverVersion',{}).get('gitVersion',''))" >> "$OUT/versions.txt"
echo "claude-harness $(git -C "$DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)" >> "$OUT/versions.txt"

NAT_KEY="$DIR/../../../test-cluster/.vagrant/machines/cp-k8s-1.36.2/virtualbox/private_key"
kubectl_nat() {
  ssh -i "$NAT_KEY" -p 60250 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=5 vagrant@127.0.0.1 \
    "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl $*" 2>/dev/null
}

scale() {
  kubectl --context $CTX -n $NS scale deploy/"$1" --replicas="$2"
  kubectl --context $CTX -n $NS rollout status deploy/"$1" --timeout=180s
  sleep 5
}

# 셀 간 쿨다운 (2026-08-06 추가). 초당 200연결을 연달아 던지면 경로에 conntrack
# 항목이 쌓여 뒤 셀의 p99가 1초대로 튀고 처리량이 떨어진다(SYN 재전송). 노드의
# nf_conntrack_tcp_timeout_time_wait=120s보다 길게 쉬어 모든 셀을 같은 조건에 둔다.
COOLDOWN="${COOLDOWN:-180}"

run() { # run <name> <extra args...>
  local name="$1"; shift
  echo "=== $name ==="
  $LG --out "$OUT/$name.json" "$@" | python3 -c "
import json,sys; d=json.load(sys.stdin)
print(f\"  ok={d['ok']} rps={d['achieved_rps']} p50={d['latency_ms']['p50']}ms \"
      f\"sloss={d['session_loss']} hloss={d['handle_loss']} rc={d['reconnects']} err={d['errors']}\")"
  sleep "$COOLDOWN"
}

kill_pod_during() { # <app> <delay> <event-file>
  local app="$1" delay="$2" evt="$3"
  sleep "$delay"
  local pod="" ok=false
  for i in 1 2 3; do
    pod=$(kubectl_nat "-n $NS get pods -l app=$app -o name" | head -1)
    if [ -n "$pod" ] && kubectl_nat "-n $NS delete $pod --wait=false" >/dev/null; then ok=true; break; fi
    sleep 3
  done
  printf '{"killed": %s, "pod": "%s", "at_s": %s}\n' "$ok" "$pod" "$delay" > "$evt"
  echo "  kill: pod=$pod ok=$ok"
}

echo "## M1: 스케일아웃 곡선 (열린 루프 ${RPS}rps, 한 번에 한 서버)"
for r in 1 2 4; do
  scale mcp-b 1; scale mcp-a "$r"
  for rep in $(seq 1 "$REPS"); do
    run "m1-a-echo-close-r${r}-rep${rep}" --url "$A_URL" --dialect a --tool echo --concurrency 16 --duration $DUR --conn-mode close --rps $RPS
    run "m1-a-echo-reuse-r${r}-rep${rep}" --url "$A_URL" --dialect a --tool echo --concurrency 16 --duration $DUR --conn-mode reuse --rps $RPS
  done
  scale mcp-a 1; scale mcp-b "$r"
  for rep in $(seq 1 "$REPS"); do
    run "m1-b-echo-close-r${r}-rep${rep}" --url "$B_URL" --dialect b --tool echo --concurrency 16 --duration $DUR --conn-mode close --rps $RPS
  done
done

echo "## M2: handle 3방식 (replicas=2, close, 열린 루프)"
scale mcp-a 1; scale mcp-b 2
for rep in $(seq 1 "$REPS"); do
  run "m2-b-mem-rep${rep}"   --url "$B_URL" --dialect b --tool counter_mem   --concurrency 8 --duration $DUR --conn-mode close --rps 100
  run "m2-b-hmac-rep${rep}"  --url "$B_URL" --dialect b --tool counter_hmac  --concurrency 8 --duration $DUR --conn-mode close --rps 100
  run "m2-b-redis-rep${rep}" --url "$B_URL" --dialect b --tool counter_redis --concurrency 8 --duration $DUR --conn-mode close --rps 100
done

echo "## M3: 파드 교체 (60s, t=20s kill, 반복 ${REPS})"
scale mcp-b 2; scale mcp-a 2
for rep in $(seq 1 "$REPS"); do
  kill_pod_during mcp-a 20 "$OUT/m3-a-kill-rep${rep}.kill.json" &
  run "m3-a-kill-rep${rep}" --url "$A_URL" --dialect a --tool echo --concurrency 8 --duration 60 --conn-mode reuse --rps 100
  wait; kubectl --context $CTX -n $NS rollout status deploy/mcp-a --timeout=120s; sleep 5
done
for rep in $(seq 1 "$REPS"); do
  kill_pod_during mcp-b 20 "$OUT/m3-b-kill-rep${rep}.kill.json" &
  run "m3-b-kill-rep${rep}" --url "$B_URL" --dialect b --tool counter_hmac --concurrency 8 --duration 60 --conn-mode close --rps 100
  wait; kubectl --context $CTX -n $NS rollout status deploy/mcp-b --timeout=120s; sleep 5
done

echo "## 집계"
"$PY" "$DIR/aggregate.py" "$OUT"
echo "완료: $OUT"
