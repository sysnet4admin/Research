#!/usr/bin/env bash
# Bring up the test-cluster and wait until MetalLB is fully applied.
# Idempotent: re-running a healthy cluster returns quickly.

set -euo pipefail
source "$(dirname "$0")/config.sh"

cd "$CLUSTER_DIR"

echo "==> vagrant up"
vagrant up

echo "==> waiting for MetalLB IPAddressPool (extra_k8s_pkgs.sh has a 600s sleep backgrounded)"
# Poll until IPAddressPool CR exists
until vagrant ssh "$CP_VM" -c \
  "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get ipaddresspool -n metallb-system --no-headers 2>/dev/null | grep -q ." \
  >/dev/null 2>&1
do
  printf '.'
  sleep 30
done
echo
echo "==> MetalLB IPAddressPool ready"

echo "==> MetalLB 풀 검증/정리 (프로비저닝 백그라운드 타이머가 셸 종료로 죽을 수 있음)"
# default 풀(.230-.250)이 없으면 적용, 잘못된 k8s-svc-pool(1.x)이 남아 있으면 삭제
if ! vagrant ssh "$CP_VM" -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get ipaddresspool default -n metallb-system" >/dev/null 2>&1; then
  vagrant ssh "$CP_VM" -c "cat <<'EOF' | sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default
  namespace: metallb-system
spec:
  addresses:
  - 192.168.2.230-192.168.2.250
EOF" 2>/dev/null
fi
vagrant ssh "$CP_VM" -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl delete ipaddresspool k8s-svc-pool -n metallb-system --ignore-not-found" 2>/dev/null || true

echo "==> final readiness check"
vagrant ssh "$CP_VM" -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide" 2>/dev/null | tail -10
