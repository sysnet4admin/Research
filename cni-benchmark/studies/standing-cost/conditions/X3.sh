#!/usr/bin/env bash
# X3: X2 + kube-proxy 대체(KPR) + native routing + masquerade (서비스 플레인 축)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

remove_kube_proxy

helm --kube-context "$CTX" upgrade -i cilium "$VENDOR_DIR/cilium-$CILIUM_VER.tgz" \
  --namespace kube-system \
  -f "$COND_DIR/values/cilium-x1.yaml" \
  -f "$COND_DIR/values/cilium-x3-extra.yaml" \
  --set hubble.enabled=false \
  --wait --timeout 8m

wait_ds_ready kube-system cilium 600
wait_nodes_ready 600
smoke_test
echo "X3 ready"
