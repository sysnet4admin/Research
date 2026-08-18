#!/usr/bin/env bash
# K1 shuffle 패치(crypto/rand -> math/rand/v2) 효과 검증 (약 60~70분).
#
# k1_pprof.sh와 동일한 재현 절차. 차이는 설치 단계뿐:
# 호스트에서 크로스 빌드한 패치 바이너리를 노드 /opt/kuberouter-fix/에 넣고
# hostPath 파일 마운트로 컨테이너의 /usr/local/bin/kube-router 위에 얹는다.
# 이미지 빌드 없이 바이너리만 교체하는 재현 방식.
#
# 사용: ./k1_fixtest.sh <OUT_DIR> <패치 바이너리 경로>
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(dirname "$DIR")"
CLUSTER="$STUDY/../../test-cluster"
OUT="${1:?OUT_DIR 필요}"
FIXBIN="${2:?패치 바이너리 경로 필요}"
CTX="cni-benchmark"
mkdir -p "$OUT"
PROG="$OUT/progress.log"
log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" | tee -a "$PROG"; }
k() { kubectl --context "$CTX" "$@"; }

source "$STUDY/conditions/lib.sh"
set +e

pprof_grab() {
  local label="$1" secs="${2:-30}"
  log "pprof 수집: $label (${secs}s)"
  nat_ssh 60351 "curl -s --max-time $((secs+15)) 'http://localhost:6060/debug/pprof/profile?seconds=${secs}' | base64" \
    | base64 -d > "$OUT/profile-$label.pb.gz"
  ls -l "$OUT/profile-$label.pb.gz" | awk '{print "  크기:", $5}' | tee -a "$PROG"
}

cpu_probe() {
  local node
  for node in cp-k8s w1-k8s w2-k8s; do
    k get --raw "/api/v1/nodes/$node/proxy/metrics/cadvisor" 2>/dev/null \
      | grep 'container_cpu_usage_seconds_total' | grep 'kube-router' \
      | sed "s/^/$(date +%s) $node /" >> "$OUT/cpu-counter.log"
  done
}

# ---- 1. 베이스 복원 ----
log "베이스 스냅샷 복원"
( cd "$CLUSTER" && vagrant snapshot restore base-no-cni ) >>"$OUT/vagrant.log" 2>&1
sleep 30
start=$SECONDS
until k get nodes >/dev/null 2>&1; do
  [ $((SECONDS - start)) -gt 600 ] && { log "ERROR: API 복원 실패"; exit 1; }
  sleep 10
done

# ---- 2. 패치 바이너리 배포 (스냅샷 복원 후여야 함) ----
log "패치 바이너리 배포 (3 노드)"
for port in 60350 60351 60352; do
  vm="cp-k8s-1.36.2"
  [ "$port" = "60351" ] && vm="w1-k8s-1.36.2"
  [ "$port" = "60352" ] && vm="w2-k8s-1.36.2"
  key="$CLUSTER_DIR/.vagrant/machines/$vm/virtualbox/private_key"
  scp -q -i "$key" -P "$port" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$FIXBIN" "vagrant@127.0.0.1:/tmp/kube-router-fix" || { log "ERROR: scp 실패 ($port)"; exit 1; }
  nat_ssh "$port" "sudo mkdir -p /opt/kuberouter-fix && sudo install -m 755 /tmp/kube-router-fix /opt/kuberouter-fix/kube-router" \
    || { log "ERROR: 설치 실패 ($port)"; exit 1; }
done
log "바이너리 배포 완료"

# ---- 3. K1 설치 (pprof) + hostPath 마운트 패치 ----
log "K1 설치 (--enable-pprof + 패치 바이너리 마운트)"
remove_kube_proxy
TMP=$(mktemp)
sed -e "s|image: docker.io/cloudnativelabs/kube-router *$|image: docker.io/cloudnativelabs/kube-router:$KUBEROUTER_VER|" \
    -e "s|- --run-service-proxy=true|- --run-service-proxy=true\n        - --enable-pprof=true|" \
    "$VENDOR_DIR/kuberouter-all-$KUBEROUTER_VER.yaml" > "$TMP"
k apply -f "$TMP"; rm -f "$TMP"
k -n kube-system patch ds kube-router --patch '{
  "spec": {"template": {"spec": {
    "volumes": [{"name": "fixbin", "hostPath": {"path": "/opt/kuberouter-fix/kube-router", "type": "File"}}],
    "containers": [{"name": "kube-router",
      "volumeMounts": [{"name": "fixbin", "mountPath": "/usr/local/bin/kube-router", "readOnly": true}]}]
  }}}}' || { log "ERROR: DS 패치 실패"; exit 1; }
sleep 10
wait_ds_ready kube-system kube-router 600
wait_nodes_ready 600
smoke_test || { log "ERROR: 스모크 실패"; exit 1; }

# 패치 바이너리가 실제로 도는지 확인 (크기 대조: 스톡과 다름)
POD=$(k -n kube-system get pods -l k8s-app=kube-router --field-selector spec.nodeName=w1-k8s -o name | head -1)
SIZE_IN=$(k -n kube-system exec "$POD" -- wc -c /usr/local/bin/kube-router 2>/dev/null | awk '{print $1}')
SIZE_FIX=$(wc -c < "$FIXBIN" | tr -d ' ')   # macOS wc는 앞 공백을 붙임
log "컨테이너 내부 바이너리 크기: $SIZE_IN (패치본 $SIZE_FIX)"
[ "$SIZE_IN" = "$SIZE_FIX" ] || { log "ERROR: 패치 바이너리 미적용"; exit 1; }
sleep 60
nat_ssh 60351 "curl -s --max-time 5 http://localhost:6060/debug/pprof/ | head -1" >/dev/null \
  || { log "ERROR: pprof 엔드포인트 응답 없음"; exit 1; }
log "안정화 300s"
sleep 300

# ---- 4. 전제 상태 + 재현 (k1_pprof.sh와 동일 타이밍) ----
export PHASE_FILE="$OUT/phase.txt"
log "전제: density(60 파드)";  "$DIR/phases.sh" density 300 >>"$PROG" 2>&1
log "전제: policy(100 NP)";    "$DIR/phases.sh" policy 150 >>"$PROG" 2>&1
log "전제: service(200 svc)";  "$DIR/phases.sh" service 300 >>"$PROG" 2>&1
sleep 60
cpu_probe
pprof_grab "pre-churn-fixed" 30

log "churn 1200s 시작"
"$DIR/phases.sh" churn 1200 >>"$PROG" 2>&1 &
CHURN_PID=$!
sleep 600
cpu_probe
pprof_grab "during-churn-fixed" 30
wait "$CHURN_PID"
log "churn 종료"

sleep 120;  cpu_probe; pprof_grab "post-churn-2min-fixed" 30
sleep 300;  cpu_probe; pprof_grab "post-churn-7min-fixed" 60
sleep 180;  cpu_probe
k delete ns loadwork --wait=false >/dev/null 2>&1
sleep 120; cpu_probe
k -n kube-system logs -l k8s-app=kube-router --tail=50 > "$OUT/logs-tail.txt" 2>&1
log "완료: $OUT"
