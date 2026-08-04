#!/usr/bin/env bash
# F1: Flannel 기본 (VXLAN, kube-proxy iptables). 전체 기준선
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP=$(mktemp)
# --iface=eth1 필수: VBox 다중 NIC에서 기본 감지가 NAT(eth0, 전 VM 동일 10.0.2.15)를
# 잡아 교차 노드 VXLAN이 불통 (파일럿 실측)
sed -e 's|10.244.0.0/16|172.16.0.0/16|' \
    -e 's|- --kube-subnet-mgr|- --kube-subnet-mgr\n        - --iface=eth1|' \
    "$VENDOR_DIR/kube-flannel-$FLANNEL_VER.yml" > "$TMP"
k apply -f "$TMP"
rm -f "$TMP"

wait_ds_ready kube-flannel kube-flannel-ds 600
wait_nodes_ready 600
smoke_test
echo "F1 ready"
