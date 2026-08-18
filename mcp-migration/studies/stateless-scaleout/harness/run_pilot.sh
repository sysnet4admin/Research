#!/usr/bin/env bash
# 파일럿 시나리오 러너 (경로 a: K8s Service LoadBalancer).
# 사용: ./run_pilot.sh <A_URL> <B_URL> <PYTHON> <OUT_DIR>
# 예:  ./run_pilot.sh http://192.168.2.230/mcp http://192.168.2.231/mcp \
#        $SCRATCH/venv/bin/python runs/pilot-2026-07-07
#
# 수치는 파일럿(Internal)이다. 발행 수치는 7/28 확정판 본측정에서만.
set -euo pipefail

A_URL="$1"; B_URL="$2"; PY="$3"; OUT="$4"
CTX="mcp-migration"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LG="$PY $DIR/loadgen.py"
mkdir -p "$OUT"

scale() { # scale <deploy> <replicas>
  kubectl --context $CTX -n $NS scale deploy/"$1" --replicas="$2"
  kubectl --context $CTX -n $NS rollout status deploy/"$1" --timeout=180s
  sleep 5
}

# 부하 중 제어 명령은 NAT ssh 경로로 보낸다 (이슈 7: vmnet 브리지가 고연결율에서
# 패킷을 드롭해 호스트 kubectl(.150 직결)이 부하 중 8% 실패. NAT 경로는 0% 검증됨)
NAT_KEY="$DIR/../../../test-cluster/.vagrant/machines/cp-k8s-1.36.2/virtualbox/private_key"
kubectl_nat() {
  ssh -i "$NAT_KEY" -p 60250 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=5 vagrant@127.0.0.1 \
    "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl $*" 2>/dev/null
}

kill_pod_during() { # kill_pod_during <app-label> <delay_s> <event-file>
  local app="$1" delay="$2" evt="$3"
  sleep "$delay"
  local pod="" ok=false
  for i in 1 2 3; do
    pod=$(kubectl_nat "-n $NS get pods -l app=$app -o name" | head -1)
    if [ -n "$pod" ] && kubectl_nat "-n $NS delete $pod --wait=false" >/dev/null; then
      ok=true; break
    fi
    sleep 3
  done
  printf '{"killed": %s, "pod": "%s", "at_s": %s}\n' "$ok" "$pod" "$delay" > "$evt"
  echo "  kill event: pod=$pod ok=$ok"
}

run() { # run <name> <extra loadgen args...>
  local name="$1"; shift
  echo "=== $name ==="
  $LG --out "$OUT/$name.json" "$@" | python3 -c "
import json,sys; d=json.load(sys.stdin)
print(f\"  ok={d['ok']} rps={d['achieved_rps']} p50={d['latency_ms']['p50']}ms \"
      f\"sloss={d['session_loss']} reinit={d['reinit']} hloss={d['handle_loss']} err={d['errors']}\")"
}

if [ -z "${SKIP_P123:-}" ]; then
echo "## P1/P2/P3: replicas=2, 방언x연결모드"
scale mcp-a 2; scale mcp-b 2
run p1-a-echo-close --url "$A_URL" --dialect a --tool echo --concurrency 8 --duration 20 --conn-mode close
run p2-a-echo-reuse --url "$A_URL" --dialect a --tool echo --concurrency 8 --duration 20 --conn-mode reuse
run p3-b-echo-close --url "$B_URL" --dialect b --tool echo --concurrency 8 --duration 20 --conn-mode close
fi

if [ -z "${SKIP_P4:-}" ]; then
echo "## P4: replicas=4 스케일아웃 (한 번에 한 서버만: 워커 CPU 총량 초과 방지 + 측정 격리)"
scale mcp-b 2; scale mcp-a 4
run p4-a-echo-reuse-r4 --url "$A_URL" --dialect a --tool echo --concurrency 8 --duration 20 --conn-mode reuse
scale mcp-a 2; scale mcp-b 4
run p4-b-echo-close-r4 --url "$B_URL" --dialect b --tool echo --concurrency 8 --duration 20 --conn-mode close
fi

echo "## P5: handle 두 방식 (replicas=2, close)"
scale mcp-a 2; scale mcp-b 2
run p5-b-counter-mem  --url "$B_URL" --dialect b --tool counter_mem  --concurrency 4 --duration 20 --conn-mode close
run p5-b-counter-hmac --url "$B_URL" --dialect b --tool counter_hmac --concurrency 4 --duration 20 --conn-mode close

echo "## P6: 파드 교체 중 (40s 부하, t=15s에 파드 1개 삭제, NAT 경로 + 이벤트 기록)"
kill_pod_during mcp-a 15 "$OUT/p6-a-echo-reuse-kill.kill.json" &
run p6-a-echo-reuse-kill --url "$A_URL" --dialect a --tool echo --concurrency 8 --duration 40 --conn-mode reuse
wait
kubectl --context $CTX -n $NS rollout status deploy/mcp-a --timeout=120s
kill_pod_during mcp-b 15 "$OUT/p6-b-hmac-close-kill.kill.json" &
run p6-b-hmac-close-kill --url "$B_URL" --dialect b --tool counter_hmac --concurrency 8 --duration 40 --conn-mode close
wait
kubectl --context $CTX -n $NS rollout status deploy/mcp-b --timeout=120s

echo "## 완료: $OUT"
ls "$OUT"
