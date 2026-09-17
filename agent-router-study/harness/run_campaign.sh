#!/usr/bin/env bash
# Agent Router 1단계 무인 캠페인.
#
# 창: 기동부터 STOP_AT까지. 사이클을 반복하고 남은 시간이 사이클 예상보다 짧으면 끝낸다.
# 사이클 하나 = 축 1 셀 전부 + 축 3 셀 전부 + 축 4 트레이스 + 축 5 프로브 + 자원 기록.
# N번째 사이클마다 부하 스윕을 한 번 더 얹는다(기본 4).
#
# 시간 결정적 동작은 전부 이 스크립트 안에 있다. 세션의 미래 행동에 기대지 않는다.
# 체크포인트를 두어 재기동하면 끝난 사이클을 건너뛴다.
#
# 사용: ./run_campaign.sh <STOP_AT "YYYY-MM-DD HH:MM"> [TAG]
set -u
STOP_AT="${1:?STOP_AT 필요. 예 \"2026-09-16 07:30\"}"
TAG="${2:-$(date +%m%d-%H%M)}"
CTX="aaif-benchmark"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
PY="$HOME/.venvs/mcpbench/bin/python"
OUT="$DIR/runs/campaign-$TAG"
mkdir -p "$OUT"
CKPT="$OUT/checkpoint.txt"
touch "$CKPT"

A_CELLS="A0 A1 A2 A3 A4 A5 A6 A7 A8 A9 A10 X1 X2 X3"
B_CELLS="B0 B1 B2 B3 B4 B5"
SETTLE="${SETTLE:-10}"      # 정책 반영 대기
N="${N:-20}"                # 셀당 호출 반복
LOAD_EVERY="${LOAD_EVERY:-4}"
LOAD_DUR="${LOAD_DUR:-45}"
RATES="${RATES:-50 100}"
RATE_DUR="${RATE_DUR:-30}"
RATE_CONC="${RATE_CONC:-16}"
SCALE_AT="${SCALE_AT:-3}"      # 이 사이클에서 복제본 2x2를 한 번 돈다
CYCLE_EST="${CYCLE_EST:-900}"   # 사이클 예상 소요(초). 남은 시간 판단에 쓴다

STOP_EPOCH=$(date -j -f "%Y-%m-%d %H:%M" "$STOP_AT" "+%s" 2>/dev/null) || {
  echo "STOP_AT 형식 오류: $STOP_AT"; exit 2; }
log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" | tee -a "$OUT/campaign.log"; }
done_mark() { grep -qxF "$1" "$CKPT"; }
mark() { echo "$1" >> "$CKPT"; }

gw_url() {
  echo "http://$(kubectl --context $CTX -n mcp-pilot get gateway ar-gw \
    -o jsonpath='{.status.addresses[0].value}')/mcp"
}

snapshot() { # snapshot <사이클>
  # local은 인자를 전부 먼저 확장하므로 한 줄에서 앞 변수를 참조하면 set -u에 걸린다.
  local c="$1"
  local f="$OUT/res-c$c.txt"
  {
    date '+%Y-%m-%d %H:%M:%S'
    kubectl --context $CTX -n envoy-gateway-system top pods 2>&1
    kubectl --context $CTX -n envoy-ai-gateway-system top pods 2>&1
    kubectl --context $CTX -n mcp-pilot top pods 2>&1
    kubectl --context $CTX get pods -A --no-headers 2>&1 | awk '$5!="0"{print "재시작:",$0}'
  } > "$f" 2>&1
}

axis5() { # axis5 <사이클> <url>
  local c="$1"
  local url="$2"
  local f="$OUT/axis5-c$c.json"
  local init
  init='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"VER","capabilities":{},"clientInfo":{"name":"p","version":"1"}}}'
  {
    echo "{"
    echo "  \"ts\": \"$(date '+%Y-%m-%dT%H:%M:%S')\","
    echo "  \"protocol_negotiation\": {"
    local first=1
    for v in 2024-11-05 2025-03-26 2025-06-18 9999-01-01; do
      local got
      got=$(curl -s -m 15 -X POST "$url" -H 'Content-Type: application/json' \
        -H 'Accept: application/json, text/event-stream' \
        -d "${init/VER/$v}" | sed -n 's/.*"protocolVersion":"\([^"]*\)".*/\1/p')
      [ $first -eq 0 ] && echo ","
      printf '    "%s": "%s"' "$v" "$got"; first=0
    done
    echo
    echo "  },"
    local code
    code=$(curl -s -m 15 -o /dev/null -w '%{http_code}' -X POST "$url" \
      -H 'Content-Type: application/json; charset=utf-8' \
      -H 'Accept: application/json, text/event-stream' -d "${init/VER/2025-06-18}")
    echo "  \"charset_content_type_code\": \"$code\","
    code=$(curl -s -m 15 -o /dev/null -w '%{http_code}' -X POST "$url" \
      -H 'Content-Type: application/json' \
      -H 'Accept: application/json, text/event-stream' -d "${init/VER/2025-06-18}")
    echo "  \"plain_content_type_code\": \"$code\""
    echo "}"
  } > "$f" 2>&1
}

# 폐루프 짝 증분. agentgateway-study가 쓴 잣대와 같게 목표 rps를 고정하고
# 직접, 대조군(MCP 프록시 없음), 게이트웨이를 한 회차 안에서 번갈아 돈다.
rate_sweep() { # rate_sweep <사이클> <접두>
  local c="$1"
  local pre="$2"
  local url gwip
  gwip="$(kubectl --context $CTX -n mcp-pilot get gateway ar-gw \
    -o jsonpath='{.status.addresses[0].value}')"
  url="http://$gwip/mcp"
  for mode in close reuse; do
    for rate in $RATES; do
      "$PY" "$DIR/harness/rategen.py" --url "http://192.168.2.101/mcp" --tool get-sum \
        --rate "$rate" --dur "$RATE_DUR" --conc "$RATE_CONC" --mode "$mode" \
        --label "$pre-direct-r$rate-$mode" \
        --out "$OUT/rate-c$c-$pre-direct-r$rate-$mode.json" 2>&1 | tee -a "$OUT/campaign.log"
      "$PY" "$DIR/harness/rategen.py" --url "http://$gwip/raw" --tool get-sum \
        --rate "$rate" --dur "$RATE_DUR" --conc "$RATE_CONC" --mode "$mode" \
        --label "$pre-envoyonly-r$rate-$mode" \
        --out "$OUT/rate-c$c-$pre-envoyonly-r$rate-$mode.json" 2>&1 | tee -a "$OUT/campaign.log"
      "$PY" "$DIR/harness/rategen.py" --url "$url" \
        --rate "$rate" --dur "$RATE_DUR" --conc "$RATE_CONC" --mode "$mode" \
        --label "$pre-gw-r$rate-$mode" \
        --out "$OUT/rate-c$c-$pre-gw-r$rate-$mode.json" 2>&1 | tee -a "$OUT/campaign.log"
    done
  done
  collect_access "$c" "$pre"
}

collect_access() { # collect_access <사이클> <접두>
  local c="$1"
  local pre="$2"
  local i=0
  for p in $(kubectl --context $CTX -n envoy-gateway-system get pods \
      -l "gateway.envoyproxy.io/owning-gateway-name=ar-gw" -o name 2>/dev/null); do
    i=$(( i + 1 ))
    kubectl --context $CTX -n envoy-gateway-system logs "$p" -c envoy --tail=20000 \
      > "$OUT/access-c$c-$pre-pod$i.log" 2>&1
  done
}

# 복제본과 트래픽 정책 2x2. 기본값(1개, Local)이 본 수치이고 나머지는 조건 표시한다.
# 제안 문서가 "어떤 인스턴스도 세션을 처리할 수 있다"고 적은 것을 여기서 확인한다.
scale_phase() { # scale_phase <사이클>
  local c="$1"
  local f
  for cfg in r1-local r1-cluster r2-local r2-cluster; do
    f="$DIR/k8s/proxy-${cfg}.yaml"
    kubectl --context $CTX apply -f "$f" >/dev/null 2>&1
    # 재조정 대기. 원하는 복제본이 Running이 될 때까지 본다(최대 5분).
    local want deadline
    want=$(echo "$cfg" | sed 's/^r\([0-9]\).*/\1/')
    deadline=$(( $(date +%s) + 300 ))
    while [ "$(kubectl --context $CTX -n envoy-gateway-system get pods \
        -l "gateway.envoyproxy.io/owning-gateway-name=ar-gw" --no-headers 2>/dev/null \
        | grep -c ' Running')" -lt "$want" ] && [ "$(date +%s)" -lt "$deadline" ]; do
      sleep 10
    done
    sleep 20
    log "확장 단계 $cfg"
    rate_sweep "$c" "$cfg"
  done
  # 기본값으로 되돌린다. 실패해도 다음 사이클이 정상 조건에서 돌게.
  kubectl --context $CTX apply -f "$DIR/k8s/proxy-r1-local.yaml" >/dev/null 2>&1
  sleep 30
}

load_sweep() { # load_sweep <사이클>
  local c="$1" url; url="$(gw_url)"
  for cond in A0 A2 A6 A9; do
    kubectl --context $CTX apply -f "$DIR/harness/cells/$cond.json" >/dev/null 2>&1
    sleep "$SETTLE"
    for conc in 1 4 16; do
      "$PY" "$DIR/harness/loadgen.py" --url "$url" --label "gw-$cond-c$conc" \
        --conc "$conc" --dur "$LOAD_DUR" --out "$OUT/load-c$c-$cond-c$conc.json" \
        2>&1 | tee -a "$OUT/campaign.log"
    done
  done
  # 기준선 둘. 백엔드 직접, 그리고 같은 Envoy를 지나되 MCP 프록시를 건너뛴 경로.
  # 뒤의 것이 오버헤드를 어느 구간에 귀속시킬지 정한다.
  local gwip
  gwip="$(kubectl --context $CTX -n mcp-pilot get gateway ar-gw \
    -o jsonpath='{.status.addresses[0].value}')"
  for conc in 1 4 16; do
    "$PY" "$DIR/harness/loadgen.py" --url "http://192.168.2.101/mcp" --tool get-sum \
      --label "direct-c$conc" --conc "$conc" --dur "$LOAD_DUR" \
      --out "$OUT/load-c$c-direct-c$conc.json" 2>&1 | tee -a "$OUT/campaign.log"
    "$PY" "$DIR/harness/loadgen.py" --url "http://$gwip/raw" --tool get-sum \
      --label "envoy-only-c$conc" --conc "$conc" --dur "$LOAD_DUR" \
      --out "$OUT/load-c$c-envoyonly-c$conc.json" 2>&1 | tee -a "$OUT/campaign.log"
  done
  # Envoy 접근 로그로 구간 귀속. 다운스트림 총시간과 업스트림 시간을 비교한다.
  kubectl --context $CTX -n envoy-gateway-system logs \
    -l "gateway.envoyproxy.io/owning-gateway-name=ar-gw" -c envoy --tail=400 \
    > "$OUT/load-c$c-envoy-access.log" 2>&1
}

log "캠페인 시작. 종료 예정 $STOP_AT. 출력 $OUT"
kubectl --context $CTX get nodes -o wide > "$OUT/env-nodes.txt" 2>&1
helm list -A --kube-context $CTX > "$OUT/env-helm.txt" 2>&1
kubectl --context $CTX get crd -o name > "$OUT/env-crds.txt" 2>&1

cycle=0
while :; do
  now=$(date +%s)
  remain=$(( STOP_EPOCH - now ))
  if [ "$remain" -lt "$CYCLE_EST" ]; then
    log "남은 시간 ${remain}초. 사이클 예상 ${CYCLE_EST}초보다 짧아 종료한다."
    break
  fi
  cycle=$(( cycle + 1 ))
  if done_mark "cycle-$cycle"; then log "사이클 $cycle 이미 완료. 건너뛴다."; continue; fi
  log "사이클 $cycle 시작 (남은 ${remain}초)"

  URL="$(gw_url)"
  if [ -z "${URL#http:///mcp}" ]; then
    log "게이트웨이 주소 없음. 60초 뒤 재시도."; sleep 60; cycle=$(( cycle - 1 )); continue
  fi

  for cell in $A_CELLS $B_CELLS; do
    kubectl --context $CTX apply -f "$DIR/harness/cells/$cell.json" >/dev/null 2>&1
    sleep "$SETTLE"
    "$PY" "$DIR/harness/probe.py" --url "$URL" --cell "$cell" --n "$N" \
      --out "$OUT/c$cycle-$cell.json" 2>&1 | tee -a "$OUT/campaign.log"
  done

  # 축 4는 두 백엔드가 붙은 B0 상태에서 잰다.
  kubectl --context $CTX apply -f "$DIR/harness/cells/B0.json" >/dev/null 2>&1
  sleep "$SETTLE"
  "$PY" "$DIR/harness/trace_probe.py" --url "$URL" --tool reflect__reflect \
    --out "$OUT/c$cycle-trace-gw.json" 2>&1 | tee -a "$OUT/campaign.log"
  "$PY" "$DIR/harness/trace_probe.py" --url "http://192.168.2.107/mcp" --tool reflect \
    --out "$OUT/c$cycle-trace-direct.json" 2>&1 | tee -a "$OUT/campaign.log"

  kubectl --context $CTX apply -f "$DIR/harness/cells/A0.json" >/dev/null 2>&1
  sleep "$SETTLE"
  "$PY" "$DIR/harness/probe.py" --url "http://192.168.2.101/mcp" --cell direct \
    --n "$N" --prefix "" --out "$OUT/c$cycle-direct.json" 2>&1 | tee -a "$OUT/campaign.log"

  axis5 "$cycle" "$URL"
  snapshot "$cycle"

  # (cycle-1) 기준이라 LOAD_EVERY=1이면 매 사이클, 4면 1 5 9번째에 돈다.
  if [ $(( (cycle - 1) % LOAD_EVERY )) -eq 0 ]; then
    log "사이클 $cycle 부하 스윕"
    load_sweep "$cycle"
    rate_sweep "$cycle" "base"
  fi

  if [ "$cycle" -eq "$SCALE_AT" ]; then
    log "사이클 $cycle 복제본과 트래픽 정책 2x2"
    scale_phase "$cycle"
  fi

  kubectl --context $CTX -n envoy-gateway-system logs \
    -l "gateway.envoyproxy.io/owning-gateway-name=ar-gw" --all-containers --tail=3000 \
    > "$OUT/c$cycle-proxy.log" 2>&1
  mark "cycle-$cycle"
  log "사이클 $cycle 완료"
  # 사이클 사이 간격. 창을 길게 쓰며 시간에 따른 변화를 본다.
  sleep "${GAP:-600}"
done

# 끝난 뒤 경로를 정책 없는 두 백엔드 상태로 되돌린다. 다음 세션이 깨진 상태를 만나지 않게.
kubectl --context $CTX apply -f "$DIR/harness/cells/B0.json" >/dev/null 2>&1
log "캠페인 종료. 사이클 $cycle 회. 경로는 B0으로 복원."
