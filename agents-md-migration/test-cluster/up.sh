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

echo "==> final readiness check"
vagrant ssh "$CP_VM" -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide" 2>/dev/null | tail -10
