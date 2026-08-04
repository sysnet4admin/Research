#!/usr/bin/env bash
# Bring up the CNI-less base cluster.
# 주의: CNI가 없으므로 노드 NotReady가 정상 종료 상태다.
set -euo pipefail
source "$(dirname "$0")/config.sh"

cd "$CLUSTER_DIR"

echo "==> vagrant up"
vagrant up

echo "==> 노드 등록 확인 (NotReady 정상)"
vagrant ssh "$CP_VM" -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes -o wide" 2>/dev/null | tail -5

echo "==> 완료. 다음: kubeconfig 병합, prefetch.sh, snapshot.sh"
