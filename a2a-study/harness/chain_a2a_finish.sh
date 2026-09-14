#!/usr/bin/env bash
# axis3 두 세대 체인이 끝난 뒤 남은 a2a 측정을 순서대로 돌린다.
# 1) 대안 대비 A2A 값의 v1.0 재측정  2) gRPC 바인딩
# 기동: caffeinate -i nohup ./harness/chain_a2a_finish.sh > /tmp/chain-a2a-finish.log 2>&1 &
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
PY="$HOME/.venvs/a2a11/bin/python"
CTX="aaif-benchmark"; NS="mcp-pilot"
say() { echo "[finish $(date '+%m-%d %H:%M')] $*"; }

"$PY" -c "import httpx, grpc" 2>/dev/null || { say "중단: venv에 httpx 또는 grpcio 없음"; exit 1; }
kubectl --context $CTX get nodes >/dev/null 2>&1 || { say "중단: 클러스터 접근 불가"; exit 1; }

# axis3 체인이 아직 돌면 끝날 때까지 기다린다. 같은 클러스터를 나눠 쓰면 둘 다 오염된다.
while pgrep -f "axis3_load_gen.sh|chain_axis3_gen.sh" >/dev/null; do
  say "axis3 체인 진행 중. 10분 뒤 다시 본다"; sleep 600
done
say "axis3 체인 없음. 남은 측정 시작"

cd "$STUDY"

# 1) 대안 대비 v1.0 바이트
OUT1="runs/axis2v10-0911"
if [ -f "$OUT1/FINDINGS.md" ] && grep -q "에이전트 카드" "$OUT1/FINDINGS.md"; then
  say "v1.0 바이트 이미 완료. 건너뛴다"
else
  say "v1.0 바이트 재측정"
  ./harness/axis2_v10_bytes.sh "$OUT1" || say "v1.0 바이트 실패(계속 진행)"
fi
sleep 60

# 2) gRPC 바인딩
OUT2="runs/grpc-0911"
mkdir -p "$OUT2"
if [ -s "$OUT2/result.json" ]; then
  say "gRPC 이미 완료. 건너뛴다"
else
  say "gRPC 서버 배포"
  kubectl --context $CTX -n $NS delete configmap grpc-arm-code >/dev/null 2>&1
  kubectl --context $CTX -n $NS create configmap grpc-arm-code \
    --from-file="$STUDY/k8s/axis2/work.py" --from-file="$STUDY/k8s/grpc/srv_a2a_grpc.py" > "$OUT2/apply.log" 2>&1
  kubectl --context $CTX apply -f "$STUDY/k8s/grpc/grpc-arm.yaml" >> "$OUT2/apply.log" 2>&1
  if kubectl --context $CTX -n $NS rollout status deploy/grpc-arm --timeout=600s >> "$OUT2/apply.log" 2>&1; then
    IP=$(kubectl --context $CTX -n $NS get svc grpc-arm -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    for i in $(seq 1 60); do curl -s --max-time 3 -o /dev/null "http://$IP:9101/.well-known/agent-card.json" && break; sleep 5; done
    sleep 10
    say "gRPC 프로브 실행 (IP $IP)"
    "$PY" ./harness/grpc_probe.py --host "$IP" --reps 30 > "$OUT2/result.json" 2>"$OUT2/error.log" \
      || say "gRPC 프로브 실패. $OUT2/error.log 참고"
    curl -s "http://$IP:9101/.well-known/agent-card.json" > "$OUT2/card.json"
  else
    say "gRPC 서버 기동 실패"
  fi
  [ "${KEEP:-0}" = "1" ] || kubectl --context $CTX delete -f "$STUDY/k8s/grpc/grpc-arm.yaml" >/dev/null 2>&1
fi
say "남은 측정 완료"
