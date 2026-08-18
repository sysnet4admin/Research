#!/usr/bin/env bash
# 주말 보강 캠페인 (2026-08-08). 본측정에서 남은 구멍을 메운다.
#
# 본측정(main-2026-08-06b)은 발행 가능한 상태지만 다섯 곳이 약하다.
#   W1 구 스펙 reuse r4의 회차 편차가 크다 (154/107/119). 반복을 늘려 좁힌다
#   W2 "몇 번째 연결에서 세션이 깨지는가"가 캡처 1회 관측뿐이다. 분포로 만든다
#   W3 신 스펙을 reuse 모드로 재 본 적이 없다. 행렬이 비대칭이다
#   W4 200rps가 "파일럿 상한의 절반"이라고만 되어 있다. 실제 상한을 잰다
#   W5 게이트웨이 경유에서 파드를 죽여 본 적이 없다. 스케일아웃만 쟀다
#
# W5는 agentgateway 설치가 필요해서 이 스크립트에 넣지 않았다. run_gateway_kill.sh 참조.
#
# 사용: ./run_weekend.sh <A_URL> <B_URL> <PYTHON> <OUT_DIR>
set -euo pipefail

A_URL="$1"; B_URL="$2"; PY="$3"; OUT="$4"
CTX="mcp-migration"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COOLDOWN="${COOLDOWN:-180}"
DUR=30
mkdir -p "$OUT"

kubectl --context $CTX -n $NS get deploy -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.containers[0].image}{"\n"}{end}' > "$OUT/versions.txt"

scale() { kubectl --context $CTX -n $NS scale deploy/"$1" --replicas="$2" >/dev/null; }

wait_ready() {
  local d="$1" n="$2" s=$SECONDS
  until [ "$(kubectl --context $CTX -n $NS get deploy "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)" = "$n" ]; do
    [ $((SECONDS - s)) -gt 300 ] && { echo "  [경고] $d 가 $n 개까지 안 뜸"; return 1; }
    sleep 5
  done
  sleep 5
}

cell() { # cell <name> <args...>
  local name="$1"; shift
  $PY "$DIR/loadgen.py" "$@" --out "$OUT/$name.json" >/dev/null 2>&1 || true
  python3 -c "
import json
try:
    d=json.load(open('$OUT/$name.json'))
    print(f\"  $name: rps={d['achieved_rps']:6.1f} p50={d['latency_ms']['p50']:5.1f} p99={d['latency_ms']['p99']:7.1f} sloss={d['session_loss']:5} hloss={d['handle_loss']:5}\")
except Exception as e:
    print(f'  $name: 읽기 실패 {e}')"
  sleep "$COOLDOWN"
}

echo "=== W1: 구 스펙 reuse r4 반복 확대 (10회) ==="
echo "본측정 3회로는 154/107/119로 흩어져 중앙값을 신뢰하기 어렵다."
scale mcp-b 1; scale mcp-a 4; wait_ready mcp-a 4 || true
for rep in $(seq 1 10); do
  cell "w1-a-reuse-r4-rep${rep}" --url "$A_URL" --dialect a --tool echo \
    --concurrency 16 --duration $DUR --conn-mode reuse --rps 200
done

echo
echo "=== W2: 세션 유실 시작 분포 (레플리카 2와 4) ==="
echo "기하분포 기댓값 N/(N-1)과 맞는지 본다."
scale mcp-a 2; wait_ready mcp-a 2 || true
$PY "$DIR/probe_onset.py" "$A_URL" 60 "$OUT/w2-onset-r2.json" || true
scale mcp-a 4; wait_ready mcp-a 4 || true
$PY "$DIR/probe_onset.py" "$A_URL" 60 "$OUT/w2-onset-r4.json" || true

echo
echo "=== W3: 신 스펙 reuse 모드 (r1/r2/r4) ==="
echo "본측정은 신 스펙을 close로만 쟀다. 행렬을 대칭으로 만든다."
scale mcp-a 1
for r in 1 2 4; do
  scale mcp-b $r; wait_ready mcp-b $r || true
  for rep in 1 2 3; do
    cell "w3-b-reuse-r${r}-rep${rep}" --url "$B_URL" --dialect b --tool echo \
      --concurrency 16 --duration $DUR --conn-mode reuse --rps 200
  done
done

echo
echo "=== W4: 신 스펙 포화점 탐색 (r4, close) ==="
echo "200rps가 상한의 어디쯤인지 수치로 말할 수 있게 한다."
scale mcp-b 4; wait_ready mcp-b 4 || true
for rps in 300 400 600 800; do
  cell "w4-b-close-r4-rps${rps}" --url "$B_URL" --dialect b --tool echo \
    --concurrency 32 --duration $DUR --conn-mode close --rps $rps
done

echo
echo "완료: $OUT"
