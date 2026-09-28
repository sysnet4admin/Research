#!/usr/bin/env bash
# 조건 설치 스크립트 공용 함수. 모든 조건 스크립트가 source 한다.
# 규약: 각 조건 스크립트는 베이스(base-no-cni) 상태에서 실행되어
# CNI를 설치하고 노드 3개가 Ready가 될 때까지 대기한 후 성공 종료한다.

set -euo pipefail

CTX="cni-benchmark"
POD_CIDR="172.16.0.0/16"
COND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY_DIR="$(dirname "$COND_DIR")"
VENDOR_DIR="$STUDY_DIR/vendor"      # 프리페치된 manifest/차트 (무인 중 네트워크 비의존)
CLUSTER_DIR="$STUDY_DIR/../../test-cluster"

# 버전 핀 (전 조건 공통)
CALICO_VER="v3.32.1"
CILIUM_VER="${CILIUM_VER:-1.19.5}"          # 2026-09-23 회차 비교부터 환경변수로 덮어쓴다
FLANNEL_VER="v0.28.7"
FLANNEL_CNI_PLUGIN_VER="v1.9.1-flannel2"
ANTREA_VER="${ANTREA_VER:-v2.6.2}"
KUBEROUTER_VER="${KUBEROUTER_VER:-v2.10.0}"   # 환경변수로 덮어쓸 수 있다(2026-09-22)

# kube-router shuffle 패치 바이너리 (#2165 제안안). 비어 있으면 스톡 이미지 그대로.
# 설정하면 K1/K2가 설치 직후 노드에 바이너리를 넣고 hostPath 로 컨테이너의
# /usr/local/bin/kube-router 위에 얹는다(k1_fixtest.sh 와 같은 방식).
KUBEROUTER_FIXBIN="${KUBEROUTER_FIXBIN:-}"

k() { kubectl --context "$CTX" "$@"; }

# NAT ssh 경로 (부하 중 제어용. vmnet 브리지 함정 회피)
# 주의: Vagrant는 VM마다 개인키가 다르다. 포트로 VM을 판별해 맞는 키를 쓴다.
nat_ssh() { # nat_ssh <port> <cmd...>
  local port="$1"; shift
  local vm="cp-k8s-1.36.2"
  [ "$port" = "60351" ] && vm="w1-k8s-1.36.2"
  [ "$port" = "60352" ] && vm="w2-k8s-1.36.2"
  ssh -n -i "$CLUSTER_DIR/.vagrant/machines/$vm/virtualbox/private_key" \
    -p "$port" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 vagrant@127.0.0.1 "$@"
}
kubectl_nat() { nat_ssh 60350 "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl $*"; }

wait_nodes_ready() { # wait_nodes_ready [timeout_s]
  local timeout="${1:-600}" start=$SECONDS
  echo "==> 노드 3개 Ready 대기 (최대 ${timeout}s)"
  while true; do
    local ready
    ready=$(k get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l | tr -d ' ')
    [ "$ready" = "3" ] && { echo "==> 노드 Ready"; return 0; }
    if [ $((SECONDS - start)) -gt "$timeout" ]; then
      echo "ERROR: 노드 Ready 시간 초과 (ready=$ready)"; k get nodes || true; return 1
    fi
    sleep 10
  done
}

wait_ds_ready() { # wait_ds_ready <namespace> <daemonset> [timeout_s]
  local ns="$1" ds="$2" timeout="${3:-600}" start=$SECONDS
  echo "==> DaemonSet $ns/$ds Ready 대기"
  while true; do
    local desired ready
    desired=$(k -n "$ns" get ds "$ds" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "")
    ready=$(k -n "$ns" get ds "$ds" -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
    [ -n "$desired" ] && [ "$desired" != "0" ] && [ "$desired" = "$ready" ] && return 0
    [ $((SECONDS - start)) -gt "$timeout" ] && { echo "ERROR: $ds 시간 초과 ($ready/$desired)"; return 1; }
    sleep 10
  done
}

# Calico operator 설치 + CRD 등록 대기 (helm 차트는 CRD 미포함, operator가 런타임 생성)
install_calico_operator() {
  echo "==> tigera-operator 적용"
  k create -f "$VENDOR_DIR/tigera-operator-manifest-$CALICO_VER.yaml" 2>/dev/null \
    || k apply --server-side -f "$VENDOR_DIR/tigera-operator-manifest-$CALICO_VER.yaml"
  echo "==> operator Ready 대기"
  k -n tigera-operator rollout status deploy/tigera-operator --timeout=180s
  echo "==> CRD(Installation) 등록 대기"
  local start=$SECONDS
  while ! k get crd installations.operator.tigera.io >/dev/null 2>&1; do
    [ $((SECONDS - start)) -gt 180 ] && { echo "ERROR: Installation CRD 미등록"; return 1; }
    sleep 5
  done
  # CRD가 등록돼도 웹훅 준비까지 잠깐 걸림
  sleep 10
}

apply_calico_cr() { # apply_calico_cr <cr-file>
  local f="$1" start=$SECONDS
  while ! k apply -f "$f" 2>/dev/null; do
    [ $((SECONDS - start)) -gt 120 ] && { echo "ERROR: CR 적용 실패 $f"; return 1; }
    sleep 5
  done
}

# kube-proxy 제거 (C2 kubeProxyManagement가 자동 처리하지 않는 조건용: X3/X4/K1)
remove_kube_proxy() {
  echo "==> kube-proxy 비활성 (nodeSelector 패치) + 규칙 정리"
  k -n kube-system patch daemonset kube-proxy -p \
    '{"spec":{"template":{"spec":{"nodeSelector":{"non-existing":"true"}}}}}'
  sleep 5
  for port in 60350 60351 60352; do
    nat_ssh "$port" "sudo iptables -t nat -F KUBE-SERVICES 2>/dev/null; sudo iptables -t nat -F KUBE-SVC 2>/dev/null; true" || true
  done
}

# ns가 Terminating이면 완전 삭제까지 대기 후 재생성 (이름 재사용 충돌 방지)
ensure_fresh_ns() { # ensure_fresh_ns <ns> [timeout_s]
  local ns="$1" timeout="${2:-180}" start=$SECONDS
  while k get ns "$ns" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q Terminating; do
    [ $((SECONDS - start)) -gt "$timeout" ] && { echo "WARN: $ns Terminating 대기 초과"; break; }
    sleep 5
  done
  k create ns "$ns" --dry-run=client -o yaml | k apply -f - >/dev/null
}

# 연결 스모크 테스트: 파드 2개(서로 다른 노드) 생성, 파드 간 ping 상당(HTTP) 확인
smoke_test() {
  echo "==> 스모크 테스트 (교차 노드 파드 통신)"
  ensure_fresh_ns smoke
  k -n smoke apply -f - <<'EOF' >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata: { name: smoke-server }
spec:
  replicas: 2
  selector: { matchLabels: { app: smoke-server } }
  template:
    metadata: { labels: { app: smoke-server } }
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          labelSelector: { matchLabels: { app: smoke-server } }
      containers:
        - name: web
          image: registry.k8s.io/e2e-test-images/agnhost:2.53
          args: ["netexec", "--http-port=8080"]
          ports: [ { containerPort: 8080 } ]
EOF
  k -n smoke rollout status deploy/smoke-server --timeout=180s >/dev/null
  local ip1 ip2
  ip1=$(k -n smoke get pods -l app=smoke-server -o jsonpath='{.items[0].status.podIP}')
  ip2=$(k -n smoke get pods -l app=smoke-server -o jsonpath='{.items[1].status.podIP}')
  # 비대화형 패턴: --rm -i는 비TTY(무인)에서 불안정 (파일럿 실측). 생성 후 로그 판독.
  k -n smoke delete pod smoke-client --ignore-not-found --wait=true >/dev/null 2>&1
  k -n smoke run smoke-client --restart=Never \
    --image=registry.k8s.io/e2e-test-images/agnhost:2.53 --command -- \
    sh -c "curl -s -m 5 http://$ip1:8080/hostname >/dev/null && curl -s -m 5 http://$ip2:8080/hostname >/dev/null && echo SMOKE_OK || echo SMOKE_FAIL" >/dev/null
  local start=$SECONDS ok=""
  while [ $((SECONDS - start)) -lt 120 ]; do
    local logs
    logs=$(k -n smoke logs smoke-client 2>/dev/null || true)
    case "$logs" in
      *SMOKE_OK*) ok=yes; break ;;
      *SMOKE_FAIL*) break ;;
    esac
    sleep 5
  done
  if [ "$ok" = "yes" ]; then
    k delete ns smoke --wait=false >/dev/null 2>&1
    echo "==> 스모크 통과"
  else
    echo "ERROR: 스모크 실패. 진단 덤프 (ns는 조사용으로 남김):"
    k -n smoke get pods -o wide 2>&1 | sed 's/^/  /'
    k -n smoke logs smoke-client 2>&1 | tail -3 | sed 's/^/  client: /'
    k -n smoke describe pod smoke-client 2>&1 | tail -8 | sed 's/^/  /'
    return 1
  fi
}

# kube-router 패치 바이너리 적용 (KUBEROUTER_FIXBIN 이 있을 때만). DS 를 만든 뒤 부른다.
# 패치 후 롤아웃이 끝나고 세 노드의 바이너리 해시가 패치본과 같은지까지 확인한다.
apply_kuberouter_fix() {
  [ -n "$KUBEROUTER_FIXBIN" ] || return 0
  [ -x "$KUBEROUTER_FIXBIN" ] || { echo "ERROR: 패치 바이너리 없음 $KUBEROUTER_FIXBIN"; return 1; }
  local want port vm key
  want=$(shasum -a 256 "$KUBEROUTER_FIXBIN" | awk '{print $1}')
  echo "==> kube-router 패치 바이너리 배포 (sha256 ${want:0:12})"
  for port in 60350 60351 60352; do
    vm="cp-k8s-1.36.2"
    [ "$port" = "60351" ] && vm="w1-k8s-1.36.2"
    [ "$port" = "60352" ] && vm="w2-k8s-1.36.2"
    key="$CLUSTER_DIR/.vagrant/machines/$vm/virtualbox/private_key"
    scp -q -i "$key" -P "$port" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      "$KUBEROUTER_FIXBIN" "vagrant@127.0.0.1:/tmp/kube-router-fix" || { echo "ERROR: scp 실패 ($port)"; return 1; }
    nat_ssh "$port" "sudo mkdir -p /opt/kuberouter-fix && sudo install -m 755 /tmp/kube-router-fix /opt/kuberouter-fix/kube-router" \
      || { echo "ERROR: 설치 실패 ($port)"; return 1; }
  done
  k -n kube-system patch ds kube-router --patch '{
    "spec": {"template": {"spec": {
      "volumes": [{"name": "fixbin", "hostPath": {"path": "/opt/kuberouter-fix/kube-router", "type": "File"}}],
      "containers": [{"name": "kube-router",
        "volumeMounts": [{"name": "fixbin", "mountPath": "/usr/local/bin/kube-router", "readOnly": true}]}]
    }}}}' || { echo "ERROR: DS 패치 실패"; return 1; }
  k -n kube-system rollout status ds/kube-router --timeout=600s || return 1
  local pod got
  for pod in $(k -n kube-system get pods -l k8s-app=kube-router -o name); do
    got=$(k -n kube-system exec "$pod" -c kube-router -- sha256sum /usr/local/bin/kube-router 2>/dev/null | awk '{print $1}')
    [ "$got" = "$want" ] || { echo "ERROR: $pod 바이너리 해시 불일치 (${got:0:12})"; return 1; }
  done
  echo "==> 패치 바이너리 확인 (파드 전부 ${want:0:12})"
}
