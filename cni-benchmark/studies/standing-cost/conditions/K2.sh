#!/usr/bin/env bash
# K2: kube-router CNI+방화벽만 (kube-proxy 유지). K1과의 차이 = 자체 IPVS 프록시 비용
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# manifest의 무태그 이미지(:latest 부동)를 버전 고정으로 치환
TMP=$(mktemp)
sed "s|image: docker.io/cloudnativelabs/kube-router *$|image: docker.io/cloudnativelabs/kube-router:$KUBEROUTER_VER|" \
  "$VENDOR_DIR/kuberouter-cni-$KUBEROUTER_VER.yaml" > "$TMP"
k apply -f "$TMP"
rm -f "$TMP"

wait_ds_ready kube-system kube-router 600
wait_nodes_ready 600
smoke_test
echo "K2 ready"
