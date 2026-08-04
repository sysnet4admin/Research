#!/usr/bin/env bash
# K1 churn 폭주 원인 재현 + 로그 확보 (1회, 약 80분).
#
# 캠페인에서 확인된 현상: K1(kube-router 전기능)이 churn에서 3.3코어로 뛰고
# 페이즈가 끝나도 복구 안 됨(5/5회 재현). K2(CNI만)는 정상 = 서비스 프록시 의심.
# 이 스크립트는 같은 전제 상태(파드 60 + NetworkPolicy 100 + Service 200)를
# 짧게 만들고 churn 동안과 이후의 kube-router 로그, IPVS/ipset/conntrack 상태를
# 60초 간격으로 수집한다. 측정용이 아니라 원인 규명용(발행 수치에 안 씀).
#
# 사용: ./k1_debug.sh <OUT_DIR>
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
set +e   # lib.sh의 -e 해제 (진단 스크립트는 개별 실패를 무시하고 계속)

snapshot_state() { # snapshot_state <label> : 노드 3개의 IPVS/ipset/conntrack 요약
  local label="$1" port
  for port in 60350 60351 60352; do
    {
      echo "=== $label node:$port $(date '+%H:%M:%S') ==="
      # 노드에 ipvsadm/ipset CLI가 없음(첫 실행에서 발견) -> /proc으로 대체
      nat_ssh "$port" "sudo grep -c '^TCP\|^UDP' /proc/net/ip_vs 2>/dev/null" \
        | sed 's/^/ipvs_services: /'
      nat_ssh "$port" "sudo grep -c '^  ->' /proc/net/ip_vs 2>/dev/null" \
        | sed 's/^/ipvs_dests: /'
      nat_ssh "$port" "sudo awk '/^  ->/ && \$4==0 {n++} END {print n+0}' /proc/net/ip_vs 2>/dev/null" \
        | sed 's/^/ipvs_weight0: /'
      nat_ssh "$port" "cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null" \
        | sed 's/^/conntrack: /'
      nat_ssh "$port" "sudo dmesg | tail -3"
    } >> "$OUT/state-$port.log" 2>&1
  done
}

cpu_probe() { # kube-router 파드별 CPU 사용 시간 스냅샷 (cadvisor 원시 counter)
  local node
  for node in cp-k8s w1-k8s w2-k8s; do
    k get --raw "/api/v1/nodes/$node/proxy/metrics/cadvisor" 2>/dev/null \
      | grep 'container_cpu_usage_seconds_total' | grep 'kube-router' \
      | sed "s/^/$(date +%s) $node /" >> "$OUT/cpu-counter.log"
  done
}

# ---- 1. 베이스 복원 + K1 설치 ----
log "베이스 스냅샷 복원"
( cd "$CLUSTER" && vagrant snapshot restore base-no-cni ) >>"$OUT/vagrant.log" 2>&1
sleep 30
start=$SECONDS
until k get nodes >/dev/null 2>&1; do
  [ $((SECONDS - start)) -gt 600 ] && { log "ERROR: API 복원 실패"; exit 1; }
  sleep 10
done
log "K1 설치"
"$STUDY/conditions/K1.sh" >>"$OUT/install.log" 2>&1 || { log "ERROR: K1 설치 실패"; exit 1; }
log "안정화 600s"
sleep 600

# ---- 2. 전제 상태 구성 (캠페인과 같은 개수, 짧은 대기) ----
export PHASE_FILE="$OUT/phase.txt"
log "전제 상태: density(60 파드)"
"$DIR/phases.sh" density 400 >>"$PROG" 2>&1
log "전제 상태: policy(100 NetworkPolicy)"
"$DIR/phases.sh" policy 200 >>"$PROG" 2>&1
log "전제 상태: service(200 Service)"
"$DIR/phases.sh" service 400 >>"$PROG" 2>&1

# ---- 3. 로그 수집 시작 (churn 전 ~ 관찰 종료까지) ----
log "kube-router 로그 스트림 시작 (3 파드)"
PIDS=()
for pod in $(k -n kube-system get pods -l k8s-app=kube-router -o name); do
  short="${pod##*/}"
  k -n kube-system logs -f "$pod" --timestamps > "$OUT/log-$short.log" 2>&1 &
  PIDS+=($!)
done
snapshot_state "pre-churn"; cpu_probe

# ---- 4. churn 20분 (캠페인과 동일) + 60초 간격 상태 스냅샷 ----
log "churn 1200s 시작"
"$DIR/phases.sh" churn 1200 >>"$PROG" 2>&1 &
CHURN_PID=$!
while kill -0 "$CHURN_PID" 2>/dev/null; do
  sleep 60
  snapshot_state "churn"; cpu_probe
done
log "churn 종료"

# ---- 5. churn 후 15분 관찰 (복구 여부가 핵심) ----
log "post-churn 관찰 900s"
end=$(( SECONDS + 900 ))
while [ $SECONDS -lt $end ]; do
  sleep 60
  snapshot_state "post-churn"; cpu_probe
done

# ---- 6. 종료 수집 ----
snapshot_state "final"
for pid in "${PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done
k -n kube-system get pods -l k8s-app=kube-router -o wide > "$OUT/pods-final.txt" 2>&1
k -n kube-system get events --sort-by=.lastTimestamp 2>/dev/null | tail -50 > "$OUT/events.txt"
log "완료. 로그: $OUT"
