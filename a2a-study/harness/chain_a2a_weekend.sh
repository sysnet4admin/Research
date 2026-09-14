#!/usr/bin/env bash
# 주말 창: 앞선 체인이 모두 끝나면 4구현(HTTP, MCP, A2A 두 세대, gRPC)으로 3회차를 더 돌린다.
# gRPC 서버가 A2A 컨테이너에 함께 떠 있어 three-arms 회차와 자원 조건이 다르다.
# 그래서 이 세트는 회차 이름을 따로 둔다(axis3four-*).
# 기동: caffeinate -i nohup ./harness/chain_a2a_weekend.sh > /tmp/chain-a2a-weekend.log 2>&1 &
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
PY="$HOME/.venvs/a2a11/bin/python"
say() { echo "[weekend $(date '+%m-%d %H:%M')] $*"; }

"$PY" -c "import httpx, grpc" 2>/dev/null || { say "중단: venv에 httpx 또는 grpcio 없음"; exit 1; }
kubectl --context aaif-benchmark get nodes >/dev/null 2>&1 || { say "중단: 클러스터 접근 불가"; exit 1; }

# 앞선 체인 둘이 다 끝날 때까지 기다린다.
while pgrep -f "axis3_load_gen.sh|chain_axis3_gen.sh|chain_a2a_finish.sh|axis2_v10_bytes.sh" >/dev/null; do
  say "앞선 체인 진행 중. 10분 뒤 다시 본다"; sleep 600
done
say "앞선 체인 없음. 4구현 회차 시작"

cd "$STUDY"
for pass in C D E; do
  OUT="runs/axis3four-0912$pass"
  if [ -f "$STUDY/$OUT/FINDINGS.md" ] && grep -q "컨테이너 로그" "$STUDY/$OUT/FINDINGS.md"; then
    say "$pass 이미 완료. 건너뛴다"; continue
  fi
  say "$pass 시작 -> $OUT"
  ./harness/axis3_load_4.sh "$PY" "$OUT"
  say "$pass 끝"
  sleep 300
done
say "주말 창 완료"
