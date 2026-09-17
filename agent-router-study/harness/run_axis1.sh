#!/usr/bin/env bash
# 축 1 셀 러너. 셀마다 MCPRoute를 갈아 끼우고 같은 배터리를 돌린다.
# 셀 사이에 정책 반영을 기다린다. 기다리지 않으면 앞 셀의 정책이 섞인다.
set -u
CTX="aaif-benchmark"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
PY="$HOME/.venvs/mcpbench/bin/python"
N="${N:-20}"
REP="${REP:-1}"
TAG="${TAG:-$(date +%m%d-%H%M)}"
CELLS="${CELLS:-A0 A1 A2 A3 A4 A5 A6 A7 A8 A9 A10}"
OUT="$DIR/runs/axis1-$TAG"
mkdir -p "$OUT"

GW="http://$(kubectl --context $CTX -n mcp-pilot get gateway ar-gw \
  -o jsonpath='{.status.addresses[0].value}')/mcp"
echo "GW=$GW  N=$N  REP=$REP  OUT=$OUT"

for rep in $(seq 1 "$REP"); do
  for cell in $CELLS; do
    kubectl --context $CTX apply -f "$DIR/harness/cells/$cell.json" >/dev/null 2>&1
    # 정책 반영 대기. 프록시가 새 설정을 받을 때까지 목록 응답이 바뀌는지 본다.
    sleep 10
    "$PY" "$DIR/harness/probe.py" --url "$GW" --cell "$cell" --n "$N" \
      --out "$OUT/$cell-r$rep.json" 2>&1 | sed "s/^/r$rep /"
  done
done

# 게이트웨이를 거치지 않은 직접 호출. 오버헤드의 기준선이다.
"$PY" "$DIR/harness/probe.py" --url "http://192.168.2.101/mcp" --cell direct --n "$N" --prefix "" \
  --out "$OUT/direct.json" 2>&1 | sed 's/^/-- /' || true

kubectl --context $CTX -n envoy-gateway-system logs \
  -l "gateway.envoyproxy.io/owning-gateway-name=ar-gw" --all-containers --tail=2000 \
  > "$OUT/proxy.log" 2>&1
echo "== 축 1 완료: $OUT =="
