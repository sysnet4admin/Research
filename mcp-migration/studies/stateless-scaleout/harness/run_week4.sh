#!/usr/bin/env bash
# 보강 주간 4부 (2026-08-10). run_week3.sh 가 끝나면 이어서 돈다.
#
# 3부까지가 "계획했던 구멍 메우기"였다면 4부는 외부 타당성 확인이다.
# 지금 모든 수치가 한 가지 클라이언트 모양(동시성 16), 한 가지 시간 창(30초),
# 한 가지 클러스터 모양(워커 2대)에서 나왔다. 셋 다 바꿔 본다.
#
#   T2  클라이언트 동시성 스윕. 유실률이 세션 개수에 좌우되는 것을 이미 봤으므로
#       우리 수치가 클라이언트 모양의 산물인지 프로토콜의 성질인지 가른다
#   T3  장시간 창. "27~49rps"의 근거가 30초짜리 10회뿐이다. 30분 창으로 재면
#       그 편차가 짧은 시간의 잡음인지 구조적인 것인지 갈린다
#   T1  워커 3대 토폴로지. 레플리카 4를 워커 2대에 올리면 파드가 노드를 공유한다.
#       "레플리카가 늘어서"와 "노드 분산이 달라져서"가 지금 섞여 있다
#
# T1이 클러스터를 바꾸므로 마지막에 둔다.
#
# 사용: ./run_week4.sh <A_URL> <B_URL> <PYTHON> <OUT_ROOT>
set -uo pipefail

A_URL="$1"; B_URL="$2"; PY="$3"; ROOT="$4"
CTX="mcp-migration"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
TC="$(cd "$STUDY/../../test-cluster" && pwd)"
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
    print(f\"    rps={d['achieved_rps']:6.1f} ok={d['ok']:6} sloss={d['session_loss']:6} \"
          f\"gwerr={d.get('gateway_error',0):5} p99={d['latency_ms']['p99']:7.1f}\")
except Exception as ex: print(f'    (읽기 실패 {ex})')" "$1"
}

cell() { local out="$1"; shift; "$PY" "$DIR/loadgen.py" "$@" --out "$out" >/dev/null 2>&1; report "$out"; sleep "$COOLDOWN"; }

while pgrep -f run_week3.sh >/dev/null; do sleep 60; done
log "3부 종료 확인. 4부 시작"

# =====================================================================
log "=== T2: 클라이언트 동시성 스윕 (레플리카 4) ==="
log "게이트웨이 실패 건수가 8개 세션 중 몇 개가 죽은 파드에 있었는지로 정확히"
log "갈렸다. 그렇다면 동시성을 바꾸면 수치도 따라 움직여야 한다. 우리 수치가"
log "클라이언트 모양의 산물인지 프로토콜의 성질인지 가른다."
OUT="$ROOT/t2-concurrency"; mkdir -p "$OUT"
for spec in a b; do
  other=$([ "$spec" = a ] && echo b || echo a)
  url=$([ "$spec" = a ] && echo "$A_URL" || echo "$B_URL")
  scale "mcp-$other" 1; scale "mcp-$spec" 4; wait_ready "mcp-$spec" 4
  for conc in 4 8 16 32; do
    log "  $spec / 동시성 $conc"
    for rep in 1 2 3; do
      cell "$OUT/t2-${spec}-c${conc}-r4-rep${rep}.json" --url "$url" --dialect "$spec" \
        --tool echo --concurrency $conc --duration 30 --conn-mode close --rps 200
    done
  done
done

# =====================================================================
log "=== T3: 장시간 창 (30분 셀) ==="
log "'구 스펙은 27~49rps'의 근거가 30초짜리 10회뿐이다. 30분 창에서도 그만큼"
log "흩어지면 구조적인 불안정이고, 좁아지면 짧은 시간의 잡음이다."
OUT="$ROOT/t3-longwindow"; mkdir -p "$OUT"
scale mcp-b 1; scale mcp-a 4; wait_ready mcp-a 4
for rep in $(seq 1 8); do
  log "  구 스펙 30분 창 $rep/8"
  cell "$OUT/t3-a-close-r4-30min-rep${rep}.json" --url "$A_URL" --dialect a --tool echo \
    --concurrency 16 --duration 1800 --conn-mode close --rps 200
done
scale mcp-a 1; scale mcp-b 4; wait_ready mcp-b 4
for rep in 1 2 3; do
  log "  신 스펙 30분 창 $rep/3 (대조)"
  cell "$OUT/t3-b-close-r4-30min-rep${rep}.json" --url "$B_URL" --dialect b --tool echo \
    --concurrency 16 --duration 1800 --conn-mode close --rps 200
done

# =====================================================================
log "=== T1: 워커 3대 토폴로지 ==="
log "레플리카 4를 워커 2대에 올리면 파드가 노드를 공유한다. 지금 데이터에는"
log "'레플리카가 늘어서'와 '노드 분산이 달라져서'가 섞여 있다. 워커를 3대로"
log "늘려 같은 셀을 다시 재면 갈린다. 새 클러스터에서 같은 수치가 나오는지도"
log "함께 확인된다(재구축 재현성)."
OUT="$ROOT/t1-topology"; mkdir -p "$OUT"

# 조인 토큰은 고정값인데 기본 TTL이 24시간이라 이미 만료됐다. 다시 만든다.
log "  조인 토큰 재생성"
vagrant ssh -c "sudo kubeadm token create 123456.1234567890123456 --ttl 24h" \
  "cp-k8s-1.36.2" -- -T 2>/dev/null | tail -2 || \
  log "  [경고] 토큰 재생성 실패. w3 조인이 안 될 수 있다"

cp "$TC/Vagrantfile" "$OUT/Vagrantfile.bak"
if sed -i '' 's/^N = 2$/N = 3/' "$TC/Vagrantfile" 2>/dev/null && grep -q "^N = 3$" "$TC/Vagrantfile"; then
  log "  워커 3대로 확장 (vagrant up w3)"
  ( cd "$TC" && vagrant up "w3-k8s-1.36.2" ) > "$OUT/vagrant-up.log" 2>&1
  s=$SECONDS
  until [ "$(kubectl --context $CTX get nodes 2>/dev/null | grep -c ' Ready ')" -ge 4 ]; do
    [ $((SECONDS - s)) -gt 900 ] && break
    sleep 15
  done
  kubectl --context $CTX get nodes -o wide > "$OUT/nodes.txt" 2>&1
  READY=$(kubectl --context $CTX get nodes 2>/dev/null | grep -c ' Ready ')
  log "  Ready 노드 $READY (기대 4 = CP1 + 워커3)"
  if [ "$READY" -ge 4 ]; then
    for spec in a b; do
      other=$([ "$spec" = a ] && echo b || echo a)
      url=$([ "$spec" = a ] && echo "$A_URL" || echo "$B_URL")
      scale "mcp-$other" 1
      for r in 2 4 6; do
        scale "mcp-$spec" $r; wait_ready "mcp-$spec" $r || continue
        log "  워커3 / $spec / 레플리카 $r"
        for rep in 1 2 3 4 5; do
          cell "$OUT/t1-${spec}-close-r${r}-rep${rep}.json" --url "$url" --dialect "$spec" \
            --tool echo --concurrency 16 --duration 30 --conn-mode close --rps 200
        done
      done
    done
    kubectl --context $CTX get pods -n $NS -o wide > "$OUT/pod-placement.txt" 2>&1
  else
    log "  [건너뜀] w3가 조인하지 못했다"
  fi

  log "  원복: w3 제거하고 Vagrantfile 되돌린다 (기준 환경은 워커 2대)"
  kubectl --context $CTX delete node w3-k8s >/dev/null 2>&1
  ( cd "$TC" && vagrant destroy -f "w3-k8s-1.36.2" ) >> "$OUT/vagrant-up.log" 2>&1
  cp "$OUT/Vagrantfile.bak" "$TC/Vagrantfile"
  scale mcp-a 2; scale mcp-b 2
else
  log "  [건너뜀] Vagrantfile 수정 실패"
  cp "$OUT/Vagrantfile.bak" "$TC/Vagrantfile" 2>/dev/null
fi

log "=== 4부 완료: $ROOT ==="
log "M4에서 계획된 측정은 여기까지다. 이후는 문서 반영 작업이라 클러스터가 필요 없다."
