#!/usr/bin/env bash
# K1: kube-router 전체 기능 (자체 IPVS 서비스 프록시, BGP 무오버레이, kube-proxy 제거)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

remove_kube_proxy

# manifest의 무태그 이미지(:latest 부동)를 버전 고정으로 치환
TMP=$(mktemp)
sed "s|image: docker.io/cloudnativelabs/kube-router *$|image: docker.io/cloudnativelabs/kube-router:$KUBEROUTER_VER|" \
  "$VENDOR_DIR/kuberouter-all-$KUBEROUTER_VER.yaml" > "$TMP"
k apply -f "$TMP"
rm -f "$TMP"

wait_ds_ready kube-system kube-router 600
wait_nodes_ready 600
smoke_test
echo "K1 ready"
