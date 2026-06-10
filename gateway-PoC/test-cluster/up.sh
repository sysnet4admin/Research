#!/usr/bin/env bash
# 클러스터 기동 + 모든 노드 Ready 후 MetalLB 적용.
# MetalLB를 CP 프로비저닝이 아니라 여기서 적용하는 이유는 metallb.sh / extra_k8s_pkgs.sh 참조.
# Idempotent: 정상 클러스터 재실행은 빠르게 반환.

set -euo pipefail
source "$(dirname "$0")/config.sh"

cd "$CLUSTER_DIR"

echo "==> vagrant up"
vagrant up

echo "==> 모든 노드(4) Ready 대기"
until [ "$(vagrant ssh "$CP_VM" -c \
  "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes --no-headers 2>/dev/null | grep -cw Ready" \
  2>/dev/null | tr -dc 0-9)" = "4" ]
do
  printf '.'
  sleep 15
done
echo
echo "==> 4개 노드 Ready"

echo "==> MetalLB 적용 (워커 조인 후라 controller 스케줄 가능)"
vagrant ssh "$CP_VM" -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf bash -s" < "$CLUSTER_DIR/metallb.sh"

echo "==> 최종 확인"
vagrant ssh "$CP_VM" -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide" 2>/dev/null | tail -6
vagrant ssh "$CP_VM" -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get ipaddresspool -n metallb-system" 2>/dev/null | tail -3
