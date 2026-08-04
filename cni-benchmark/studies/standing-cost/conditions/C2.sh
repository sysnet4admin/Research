#!/usr/bin/env bash
# C2: Calico operator eBPF, VXLAN, kube-proxy 자동 관리(kubeProxyManagement)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

install_calico_operator
apply_calico_cr "$COND_DIR/cr/calico-c2.yaml"

wait_ds_ready calico-system calico-node 600
wait_nodes_ready 600
k -n kube-system get ds kube-proxy -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null | \
  xargs -I{} echo "kube-proxy desired={} (0이면 자동 정리됨)"
smoke_test
echo "C2 ready"
