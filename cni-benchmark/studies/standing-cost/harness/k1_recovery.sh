#!/usr/bin/env bash
# K1 히스테리시스가 자연 회복하는 데 얼마나 걸리는지 관찰한다 (약 2시간 30분).
#
# k1_pprof.sh의 최소 델타 사본이다. churn 까지는 같고, 그 뒤에 오브젝트를
# 지우지 않은 채 최대 90분을 관찰한다. 제보에서 "언젠가는 내려가지 않느냐"는
# 물음에 답할 근거를 만드는 것이 목적이다. 측정용 아님(수치 발행 금지).
#
# 사용: ./k1_recovery.sh <OUT_DIR>
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(dirname "$DIR")"
CLUSTER="$STUDY/../../test-cluster"
OUT="${1:?OUT_DIR 필요}"
CTX="cni-benchmark"
mkdir -p "$OUT"
PROG="$OUT/progress.log"
log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" | tee -a "$PROG"; }
k() { kubectl --context "$CTX" "$@"; }

source "$STUDY/conditions/lib.sh"
set +e   # lib.sh의 -e 해제

pprof_grab() { # pprof_grab <label> <seconds>  : w1 노드에서 CPU 프로파일 수집
  local label="$1" secs="${2:-30}"
  log "pprof 수집: $label (${secs}s)"
  nat_ssh 60351 "curl -s --max-time $((secs+15)) 'http://localhost:6060/debug/pprof/profile?seconds=${secs}' | base64" \
    | base64 -d > "$OUT/profile-$label.pb.gz"
  nat_ssh 60351 "curl -s --max-time 15 'http://localhost:6060/debug/pprof/goroutine?debug=1'" \
    > "$OUT/goroutine-$label.txt"
  ls -l "$OUT/profile-$label.pb.gz" | awk '{print "  크기:", $5}' | tee -a "$PROG"
}

cpu_probe() { # kube-router CPU counter 스냅샷 (히스테리시스 재현 확인용)
  local node
  for node in cp-k8s w1-k8s w2-k8s; do
    k get --raw "/api/v1/nodes/$node/proxy/metrics/cadvisor" 2>/dev/null \
      | grep 'container_cpu_usage_seconds_total' | grep 'kube-router' \
      | sed "s/^/$(date +%s) $node /" >> "$OUT/cpu-counter.log"
  done
}

# ---- 1. 베이스 복원 + K1(+pprof) 설치 ----
if [ "${SKIP_RESTORE:-0}" = "1" ]; then
  log "베이스 스냅샷 복원 건너뜀 (SKIP_RESTORE=1)"
else
  log "베이스 스냅샷 복원"
  ( cd "$CLUSTER" && vagrant snapshot restore base-no-cni ) >>"$OUT/vagrant.log" 2>&1
  sleep 30
fi
start=$SECONDS
until k get nodes >/dev/null 2>&1; do
  elapsed=$((SECONDS - start))
  log "API 대기 ${elapsed}s: $(k get nodes 2>&1 | head -1 | cut -c1-120)"
  [ $elapsed -gt 600 ] && { log "ERROR: API 복원 실패"; exit 1; }
  sleep 10
done
log "API 응답 확인"

log "K1 설치 (--enable-pprof 추가)"
remove_kube_proxy
TMP=$(mktemp)
sed -e "s|image: docker.io/cloudnativelabs/kube-router *$|image: docker.io/cloudnativelabs/kube-router:$KUBEROUTER_VER|" \
    -e "s|- --run-service-proxy=true|- --run-service-proxy=true\n        - --enable-pprof=true|" \
    "$VENDOR_DIR/kuberouter-all-$KUBEROUTER_VER.yaml" > "$TMP"
grep -q "enable-pprof" "$TMP" || { log "ERROR: pprof 플래그 삽입 실패"; exit 1; }
k apply -f "$TMP"; rm -f "$TMP"
wait_ds_ready kube-system kube-router 600
wait_nodes_ready 600
smoke_test || { log "ERROR: 스모크 실패"; exit 1; }
sleep 60
nat_ssh 60351 "curl -s --max-time 5 http://localhost:6060/debug/pprof/ | head -1" >/dev/null \
  || { log "ERROR: pprof 엔드포인트 응답 없음"; exit 1; }
log "pprof 엔드포인트 확인됨"
log "안정화 300s"
sleep 300

# ---- 2. 전제 상태 (캠페인과 같은 오브젝트 수) ----
export PHASE_FILE="$OUT/phase.txt"
log "전제: density(60 파드)";  "$DIR/phases.sh" density 300 >>"$PROG" 2>&1
log "전제: policy(100 NP)";    "$DIR/phases.sh" policy 150 >>"$PROG" 2>&1
log "전제: service(200 svc)";  "$DIR/phases.sh" service 300 >>"$PROG" 2>&1
sleep 60
cpu_probe
pprof_grab "pre-churn" 30

# ---- 3. churn 1200s (검증된 재현 조건 유지) + 중간 프로파일 ----
log "churn 1200s 시작"
"$DIR/phases.sh" churn 1200 >>"$PROG" 2>&1 &
CHURN_PID=$!
sleep 600
cpu_probe
pprof_grab "during-churn" 30
wait "$CHURN_PID"
log "churn 종료"

# ---- 4. churn 후: 오브젝트를 둔 채 최대 90분 관찰 ----
CHURN_END=$SECONDS

cpu_now() { # w1의 kube-router CPU를 10초 창으로 잰다 (코어 단위)
  nat_ssh 60351 'p=$(pgrep -x kube-router|head -1); [ -z "$p" ] && { echo NA; exit; }
a=$(awk "{print \$14+\$15}" /proc/$p/stat); sleep 10
b=$(awk "{print \$14+\$15}" /proc/$p/stat)
echo "scale=3; ($b-$a)/100/10" | bc' 2>/dev/null | tr -d '\r'
}

for M in 2 7 15 30 45 60 75 90; do
  TARGET=$((CHURN_END + M*60))
  while [ $SECONDS -lt $TARGET ]; do sleep 20; done
  C=$(cpu_now)
  log "post-churn ${M}분: ${C:-NA} 코어"
  echo "$M ${C:-NA}" >> "$OUT/recovery-curve.txt"
  cpu_probe
  case "$M" in
    2|7|30|90) pprof_grab "post-churn-${M}min" 30 ;;
  esac
done
log "90분 관찰 종료"

# ---- 5. 오브젝트 삭제 후 복귀 확인 ----
k delete ns loadwork --wait=false >/dev/null 2>&1
sleep 120; cpu_probe
log "삭제 후: $(cpu_now) 코어"
pprof_grab "after-delete" 30
k -n kube-system logs -l k8s-app=kube-router --tail=100 > "$OUT/logs-tail.txt" 2>&1
log "완료: $OUT"
