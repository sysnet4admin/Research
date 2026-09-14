#!/usr/bin/env bash
# 주말 무인 창: axis3 두 세대판을 2회 연속 돌린다(회차 드리프트 확인용).
# 기동: caffeinate -i nohup ./harness/chain_axis3_gen.sh > /tmp/chain-a2a-gen.log 2>&1 &
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
PY="$HOME/.venvs/a2a11/bin/python"
say() { echo "[chain $(date '+%m-%d %H:%M')] $*"; }

# 전제 검사: venv와 클러스터가 없으면 시작하지 않는다.
"$PY" -c "import httpx" 2>/dev/null || { say "중단: $PY 에 httpx 없음"; exit 1; }
kubectl --context aaif-benchmark get nodes >/dev/null 2>&1 || { say "중단: 클러스터 접근 불가"; exit 1; }

for pass in A B; do
  OUT="runs/axis3gen-0911$pass"
  if [ -f "$STUDY/$OUT/FINDINGS.md" ] && grep -q "컨테이너 로그" "$STUDY/$OUT/FINDINGS.md"; then
    say "$pass 이미 완료. 건너뛴다"; continue
  fi
  say "$pass 시작 -> $OUT"
  cd "$STUDY" && ./harness/axis3_load_gen.sh "$PY" "$OUT"
  say "$pass 끝"
  sleep 300
done
say "체인 완료"
