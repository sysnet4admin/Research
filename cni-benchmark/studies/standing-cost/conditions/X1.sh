#!/usr/bin/env bash
# X1: Cilium helm 기본 (veth, VXLAN, Hubble on, kube-proxy 유지)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

helm --kube-context "$CTX" upgrade -i cilium "$VENDOR_DIR/cilium-$CILIUM_VER.tgz" \
  --namespace kube-system \
  -f "$COND_DIR/values/cilium-x1.yaml" --wait --timeout 8m

wait_ds_ready kube-system cilium 600
wait_nodes_ready 600
smoke_test
echo "X1 ready"
