#!/usr/bin/env bash
# 보강 주간 3부 (2026-08-10). run_week2.sh 가 끝나면 이어서 돈다.
#
# 여기부터는 클러스터 구성을 건드린다. 되돌릴 수 있는 순서로 배치했다.
#   S3  경로 (b) Gateway API 구현체 경유. 설치했다가 지운다
#   S2  kube-proxy nftables 모드. 클러스터 전체 설정
#   V8  튜토리얼 재현 검증. 스냅샷 복원이라 S2도 함께 원복된다
#
# 사용: ./run_week3.sh <A_URL> <B_URL> <PYTHON> <OUT_ROOT>
set -uo pipefail

A_URL="$1"; B_URL="$2"; PY="$3"; ROOT="$4"
CTX="mcp-migration"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
PROJ="$(cd "$STUDY/../.." && pwd)"
COOLDOWN="${COOLDOWN:-180}"
mkdir -p "$ROOT"

log() { echo "[$(date '+%m-%d %H:%M')] $*"; }
scale() { kubectl --context $CTX -n $NS scale deploy/"$1" --replicas="$2" >/dev/null 2>&1; }

wait_ready() {
  local d="$1" n="$2" s=$SECONDS
  until [ "$(kubectl --context $CTX -n $NS get deploy "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)" = "$n" ]; do
    [ $((SECONDS - s)) -gt 300 ] && { log "  [경고] $d 가 $n 개까지 안 뜸"; return 1; }
    sleep 5
  done
  sleep 5
}

report() {
  python3 -c "
import json,sys
try:
    d=json.load(open(sys.argv[1]))
    print(f\"    rps={d['achieved_rps']:6.1f} sloss={d['session_loss']:5} gwerr={d.get('gateway_error',0):5} \"
          f\"hloss={d['handle_loss']:5} p99={d['latency_ms']['p99']:7.1f} {dict(d.get('errors') or {})}\")
except Exception as ex: print(f'    (읽기 실패 {ex})')" "$1"
}

cell() { local out="$1"; shift; "$PY" "$DIR/loadgen.py" "$@" --out "$out" >/dev/null 2>&1; report "$out"; sleep "$COOLDOWN"; }

while pgrep -f run_week2.sh >/dev/null; do sleep 60; done
log "2부 종료 확인. 3부 시작"

# =====================================================================
log "=== S3: 경로 (b) Gateway API 구현체 경유 ==="
log "지금 한계 절에 '측정하지 않았다'로 적혀 있는 항목. 게이트웨이 질문을"
log "agentgateway 하나로만 답한 상태라 일반 Gateway API 구현체도 본다."
log "agentgateway와 달리 MCP를 모르는 순수 L7 프록시라 세션 개념이 없다."
OUT="$ROOT/s3-gatewayapi"; mkdir -p "$OUT"
GWDIR="$PROJ/../gateway-PoC/implementations"
if [ -f "$GWDIR/nginx/install.sh" ]; then
  log "  nginx Gateway Fabric 설치 (KUBE_CONTEXT를 명시해 넘긴다. 기본값이"
  log "  gateway-PoC라서 안 넘기면 다른 클러스터에 깔린다)"
  ( cd "$GWDIR/nginx" && KUBE_CONTEXT=$CTX bash install.sh ) > "$OUT/install.log" 2>&1
  sleep 30
  kubectl --context $CTX apply -f "$STUDY/k8s/gatewayapi-route.yaml" > "$OUT/route.log" 2>&1
  sleep 20
  BGW=$(kubectl --context $CTX -n $NS get gateway mcp-httproute-gw -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
  if [ -n "$BGW" ]; then
    log "  경로 (b) 주소: $BGW"
    scale mcp-b 1; scale mcp-a 4; wait_ready mcp-a 4
    for rep in 1 2 3; do
      cell "$OUT/s3-a-close-r4-rep${rep}.json" --url "http://$BGW/a/mcp" --dialect a --tool echo \
        --concurrency 16 --duration 30 --conn-mode close --rps 200
    done
    scale mcp-a 1; scale mcp-b 4; wait_ready mcp-b 4
    for rep in 1 2 3; do
      cell "$OUT/s3-b-close-r4-rep${rep}.json" --url "http://$BGW/b/mcp" --dialect b --tool echo \
        --concurrency 16 --duration 30 --conn-mode close --rps 200
    done
  else
    log "  [건너뜀] Gateway 주소를 못 받았다"
  fi
  log "  정리: nginx 제거 (격리 복원)"
  kubectl --context $CTX delete -f "$STUDY/k8s/gatewayapi-route.yaml" >/dev/null 2>&1
  ( cd "$GWDIR/nginx" && KUBE_CONTEXT=$CTX bash install.sh --uninstall ) >> "$OUT/install.log" 2>&1 || \
    helm --kube-context $CTX uninstall ngf -n nginx-gateway >/dev/null 2>&1
  sleep 20
else
  log "  [건너뜀] gateway-PoC nginx 설치 스크립트를 못 찾았다"
fi

# =====================================================================
log "=== S2: kube-proxy nftables 모드 ==="
log "cni 연구에서 nftables가 kube-proxy 메모리를 70% 줄인다는 것은 쟀지만"
log "세션 유실 거동이 iptables와 다른지는 안 봤다. 두 연구가 이어지는 지점."
OUT="$ROOT/s2-nftables"; mkdir -p "$OUT"
kubectl --context $CTX -n kube-system get cm kube-proxy -o yaml > "$OUT/kube-proxy-backup.yaml" 2>&1
if kubectl --context $CTX -n kube-system get cm kube-proxy -o yaml \
   | sed 's/^\( *\)mode: ".*"/\1mode: "nftables"/' \
   | kubectl --context $CTX apply -f - >/dev/null 2>&1; then
  kubectl --context $CTX -n kube-system rollout restart ds/kube-proxy >/dev/null 2>&1
  kubectl --context $CTX -n kube-system rollout status ds/kube-proxy --timeout=300s >/dev/null 2>&1
  sleep 30
  MODE=$(kubectl --context $CTX -n kube-system logs ds/kube-proxy --tail=200 2>/dev/null | grep -io "nftables" | head -1)
  log "  전환 확인: ${MODE:-불명}"
  if $PY "$DIR/loadgen.py" --url "$A_URL" --dialect a --tool echo --concurrency 4 \
       --duration 5 --conn-mode close --rps 20 --out "$OUT/smoke.json" >/dev/null 2>&1; then
    log "  스모크 통과. 본 측정 시작"
    scale mcp-b 1; scale mcp-a 4; wait_ready mcp-a 4
    for rep in 1 2 3 4 5; do
      cell "$OUT/s2-a-close-r4-rep${rep}.json" --url "$A_URL" --dialect a --tool echo \
        --concurrency 16 --duration 30 --conn-mode close --rps 200
    done
    scale mcp-a 1; scale mcp-b 4; wait_ready mcp-b 4
    for rep in 1 2 3 4 5; do
      cell "$OUT/s2-b-close-r4-rep${rep}.json" --url "$B_URL" --dialect b --tool echo \
        --concurrency 16 --duration 30 --conn-mode close --rps 200
    done
    $PY "$DIR/probe_onset.py" "$A_URL" 60 "$OUT/s2-onset-r4.json" 2>&1 | tail -3
  else
    log "  [중단] nftables 전환 뒤 스모크 실패. 아래 V8이 스냅샷으로 원복한다"
  fi
else
  log "  [건너뜀] kube-proxy ConfigMap 수정 실패"
fi

# =====================================================================
log "=== V8: 튜토리얼 재현 검증 ==="
log "발행문이 재현 가능하다고 주장하므로 문서에 적은 순서 그대로 해 본다."
log "기동 -> 스냅샷 복원 -> 이미지 빌드/적재 -> 배포. 스냅샷 복원이 S2도 원복한다."
OUT="$ROOT/v8-repro"; mkdir -p "$OUT"
{
  echo "== 1. 스냅샷 복원 =="
  ( cd "$PROJ/test-cluster" && bash reset.sh ) 2>&1 | tail -20
  echo "== 2. 이미지 빌드와 적재 =="
  ( cd "$STUDY" && bash images/build_and_load.sh ) 2>&1 | tail -20
  echo "== 3. 배포 =="
  ( cd "$STUDY" && bash k8s/deploy.sh ) 2>&1 | tail -20
} > "$OUT/repro.log" 2>&1
sleep 30
echo "== 4. 최소 클라이언트로 양쪽 확인 ==" >> "$OUT/repro.log"
"$PY" "$STUDY/examples/minimal_client.py" old "$A_URL" >> "$OUT/repro.log" 2>&1
"$PY" "$STUDY/examples/minimal_client.py" new "$B_URL" >> "$OUT/repro.log" 2>&1
echo "== 5. 페이로드 캡처 재현 ==" >> "$OUT/repro.log"
scale mcp-a 2; scale mcp-b 2; wait_ready mcp-a 2; wait_ready mcp-b 2
"$PY" "$DIR/capture.py" "$A_URL" "$B_URL" "$OUT/payloads" >> "$OUT/repro.log" 2>&1
tail -12 "$OUT/repro.log"

log "=== 3부 완료: $ROOT ==="
