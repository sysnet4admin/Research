#!/usr/bin/env bash
# X2: X1 + Hubble off (관측 비용 분리)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

helm --kube-context "$CTX" upgrade -i cilium "$VENDOR_DIR/cilium-$CILIUM_VER.tgz" \
  --namespace kube-system \
  -f "$COND_DIR/values/cilium-x1.yaml" \
  --set hubble.enabled=false \
  --wait --timeout 8m

wait_ds_ready kube-system cilium 600
wait_nodes_ready 600
smoke_test
echo "X2 ready"
