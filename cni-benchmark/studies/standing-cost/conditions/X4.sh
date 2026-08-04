#!/usr/bin/env bash
# X4: X3 + netkit 장치 (디바이스 타입만 차이. beta 기능, 결과에 명시)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# 게이트: 워커 커널의 CONFIG_NETKIT 확인
nat_ssh 60351 'grep -q "CONFIG_NETKIT=y" /boot/config-$(uname -r)' \
  || { echo "ERROR: CONFIG_NETKIT=y 아님, X4 불가"; exit 1; }

remove_kube_proxy

helm --kube-context "$CTX" upgrade -i cilium "$VENDOR_DIR/cilium-$CILIUM_VER.tgz" \
  --namespace kube-system \
  -f "$COND_DIR/values/cilium-x1.yaml" \
  -f "$COND_DIR/values/cilium-x3-extra.yaml" \
  --set hubble.enabled=false \
  --set bpf.datapathMode=netkit \
  --wait --timeout 8m

wait_ds_ready kube-system cilium 600
wait_nodes_ready 600
smoke_test
echo "X4 ready"
