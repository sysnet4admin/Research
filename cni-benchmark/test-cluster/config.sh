#!/usr/bin/env bash
# Single source of truth for test-cluster paths and names.

set -euo pipefail

CLUSTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# kubectl context name bound to this cluster
KUBE_CONTEXT="cni-benchmark"

CP_VM="cp-k8s-1.36.2"
WORKER_VMS=("w1-k8s-1.36.2" "w2-k8s-1.36.2")
ALL_VMS=("$CP_VM" "${WORKER_VMS[@]}")

# NAT ssh 포트 (부하 중 제어는 이 경로. vmnet 브리지 함정 회피)
CP_SSH_PORT=60350
W1_SSH_PORT=60351
W2_SSH_PORT=60352

# Baseline snapshot name (CNI 없는 상태 + 이미지 프리페치 완료)
BASELINE_SNAPSHOT="base-no-cni"

export CLUSTER_DIR KUBE_CONTEXT CP_VM BASELINE_SNAPSHOT CP_SSH_PORT W1_SSH_PORT W2_SSH_PORT
