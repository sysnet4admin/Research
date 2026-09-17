#!/usr/bin/env bash
# PBKDF2 반복 횟수가 MCP 프록시 지연과 처리량에 무엇을 하는지 잰다.
# 부하가 도는 동안 kubectl top을 반복 표본으로 읽어 CPU 모순도 같이 푼다.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
PY="$HOME/.venvs/mcpbench/bin/python"
CTX="aaif-benchmark"
NS="envoy-gateway-system"
SEL='gateway.envoyproxy.io/owning-gateway-name=ar-gw'
URL="${URL:?URL 필요}"
ITER="${1:?반복 횟수 필요}"
OUT="$DIR/runs/crypto-$ITER"
mkdir -p "$OUT"

echo "=== 반복 $ITER 회차 시작 $(date +%H:%M:%S) ==="

# 실제로 그 값으로 돌고 있는지 확인한다. 확인 없이 재면 무엇을 잰 것인지 모른다.
ARG=$(kubectl --context "$CTX" -n "$NS" get pods -l "$SEL" \
  -o jsonpath='{.items[0].spec.initContainers[?(@.name=="ai-gateway-extproc")].args}' \
  | tr ',' '\n' | grep -A1 mcpSessionEncryptionIterations | tr -d '"[] \n')
echo "사이드카 인자: $ARG"
case "$ARG" in *"$ITER"*) : ;; *) echo "반복 횟수가 $ITER 이 아니다. 중단."; exit 1 ;; esac

# 부하가 도는 동안 CPU를 표본으로 읽는다. metrics-server 집계 창이 15~60초라
# 부하를 180초 이어서 걸고 그 안에서 15초마다 읽는다.
sample_top() {
  local n=$1 f="$OUT/top.txt"
  : > "$f"
  for i in $(seq 1 "$n"); do
    { date +%H:%M:%S; kubectl --context "$CTX" -n "$NS" top pod -l "$SEL" \
        --containers --no-headers 2>/dev/null; } >> "$f"
    sleep 15
  done
}

echo "-- 지속 포화 부하 180초 (동시 16), CPU 표본 동시 수집"
sample_top 12 &
TOPPID=$!
"$PY" "$DIR/loadgen.py" --url "$URL" --conc 16 --dur 180 \
  --label "sat-$ITER" --out "$OUT/sat.json"
wait $TOPPID 2>/dev/null
echo "-- CPU 표본"
cat "$OUT/top.txt"

echo "-- 저부하 지연 (동시 1, 30초)"
"$PY" "$DIR/loadgen.py" --url "$URL" --conc 1 --dur 30 \
  --label "c1-$ITER" --out "$OUT/c1.json"

echo "-- 목표 고정 회차"
for r in 50 100; do
  for m in close reuse; do
    "$PY" "$DIR/rategen.py" --url "$URL" --rate "$r" --dur 60 --conc 16 \
      --mode "$m" --label "r$r-$m-$ITER" --out "$OUT/r$r-$m.json"
  done
done
echo "=== 반복 $ITER 회차 끝 $(date +%H:%M:%S) ==="
