#!/usr/bin/env bash
# 무인 창 기동. 사전 점검을 통과해야만 캠페인이 뜬다.
# 절전 방지(caffeinate)와 세션 분리(nohup + disown)를 여기서 건다.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
STOP_AT="${1:?STOP_AT 필요. 예 \"2026-09-16 07:30\"}"
TAG="${2:-$(date +%m%d-%H%M)}"

"$DIR/preflight.sh" || { echo "사전 점검 실패. 기동하지 않는다."; exit 1; }

# 기본 배포 상태에서 출발한다. 앞선 확인 작업이 복제본이나 트래픽 정책을 바꿔 놓았을
# 수 있는데 그대로 시작하면 본 수치가 기본값이 아니게 된다.
CTX="aaif-benchmark"
kubectl --context "$CTX" apply -f "$(dirname "$DIR")/k8s/proxy-r1-local.yaml" >/dev/null 2>&1
kubectl --context "$CTX" apply -f "$(dirname "$DIR")/harness/cells/A0.json" >/dev/null 2>&1
echo "기본값 복원 대기(복제본 1, externalTrafficPolicy Local)"
DEADLINE=$(( $(date +%s) + 300 ))
while [ "$(kubectl --context "$CTX" -n envoy-gateway-system get pods \
    -l 'gateway.envoyproxy.io/owning-gateway-name=ar-gw' --no-headers 2>/dev/null \
    | grep -c ' Running')" -ne 1 ] && [ "$(date +%s)" -lt "$DEADLINE" ]; do sleep 10; done
REP=$(kubectl --context "$CTX" -n envoy-gateway-system get deploy \
  -l 'gateway.envoyproxy.io/owning-gateway-name=ar-gw' -o jsonpath='{.items[0].spec.replicas}')
ETP=$(kubectl --context "$CTX" -n envoy-gateway-system get svc \
  -l 'gateway.envoyproxy.io/owning-gateway-name=ar-gw' -o jsonpath='{.items[0].spec.externalTrafficPolicy}')
echo "출발 상태: 복제본=$REP externalTrafficPolicy=$ETP"
[ "$REP" = "1" ] && [ "$ETP" = "Local" ] || { echo "기본값 복원 실패. 기동하지 않는다."; exit 1; }

export N="${N:-20}" SETTLE="${SETTLE:-10}" GAP="${GAP:-1200}" \
       LOAD_EVERY="${LOAD_EVERY:-4}" LOAD_DUR="${LOAD_DUR:-45}" \
       CYCLE_EST="${CYCLE_EST:-1800}" RATES="${RATES:-50 100}" \
       RATE_DUR="${RATE_DUR:-30}" RATE_CONC="${RATE_CONC:-16}" \
       SCALE_AT="${SCALE_AT:-3}"
echo "설정: N=$N SETTLE=$SETTLE GAP=$GAP LOAD_EVERY=$LOAD_EVERY LOAD_DUR=$LOAD_DUR"
echo "      RATES=$RATES RATE_DUR=$RATE_DUR RATE_CONC=$RATE_CONC SCALE_AT=$SCALE_AT"
echo "종료 예정: $STOP_AT  태그: $TAG"

caffeinate -i nohup "$DIR/run_campaign.sh" "$STOP_AT" "$TAG" \
  > "/tmp/ar-campaign-$TAG.log" 2>&1 &
PID=$!
disown
sleep 20
if kill -0 "$PID" 2>/dev/null; then
  echo "기동 확인. PID=$PID  로그 /tmp/ar-campaign-$TAG.log"
  tail -5 "/tmp/ar-campaign-$TAG.log"
else
  echo "기동 실패. 로그를 본다."; tail -20 "/tmp/ar-campaign-$TAG.log"; exit 1
fi
