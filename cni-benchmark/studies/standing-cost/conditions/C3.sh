#!/usr/bin/env bash
# C3: Calico 클래식 manifest, VXLAN backend (BIRD 없음), Typha 없음
# 원본 calico.yaml에서 변경: CIDR 172.16.0.0/16, IPIP->Never, VXLAN->Always,
# backend bird->vxlan, bird 프로브 제거 (Calico 문서의 VXLAN-only 표준 변형)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP=$(mktemp)
sed \
  -e 's/# - name: CALICO_IPV4POOL_CIDR/- name: CALICO_IPV4POOL_CIDR/' \
  -e 's|#   value: "192.168.0.0/16"|  value: "172.16.0.0/16"|' \
  -e 's/value: "Always"/value: "Never"/' \
  -e '/CALICO_IPV4POOL_VXLAN/{n;s/value: "Never"/value: "Always"/;}' \
  -e 's/calico_backend: "bird"/calico_backend: "vxlan"/' \
  -e 's/-bird-live//' \
  -e 's/-bird-ready//' \
  -e 's|- name: CLUSTER_TYPE|- name: IP_AUTODETECTION_METHOD\n              value: "interface=eth1"\n            - name: CLUSTER_TYPE|' \
  "$VENDOR_DIR/calico-$CALICO_VER.yaml" > "$TMP"
# IP_AUTODETECTION_METHOD=interface=eth1: VBox 다중 NIC에서 first-found가
# NAT(eth0)를 잡으면 VXLAN 터널 엔드포인트가 전 노드 동일 IP가 되는 함정 방지

k apply -f "$TMP"
rm -f "$TMP"

wait_ds_ready kube-system calico-node 600
wait_nodes_ready 600
smoke_test
echo "C3 ready"
