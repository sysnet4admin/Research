#!/usr/bin/env bash

##### Addtional configuration for All-in-one >> replace to extra-k8s-pkgs
EXTRA_PKGS_ADDR="https://raw.githubusercontent.com/sysnet4admin/IaC/main/k8s/extra-pkgs/v1.35"

curl $EXTRA_PKGS_ADDR/get_helm_v4.0.4.sh | bash
# helm completion on bash-completion dir & alias+
helm completion bash > /etc/bash_completion.d/helm
echo 'alias h=helm' >> ~/.bashrc
echo 'complete -F __start_helm h' >> ~/.bashrc

# metallb v0.15.3
kubectl apply -f $EXTRA_PKGS_ADDR/metallb-native-v0.15.3.yaml

# split metallb CRD due to it cannot apply at once.
# it looks like Operator limitation
# QA:
# - 240sec cannot deploy on intel MAC. So change Seconds
# - 300sec can deploy but safety range is from 540 - 600

# config metallb layer2 mode
(sleep 540 && kubectl apply -f $EXTRA_PKGS_ADDR/metallb-l2mode.yaml)&
# config metallb ip range and it cannot deploy now due to CRD cannot create yet
(sleep 600 && kubectl apply -f $EXTRA_PKGS_ADDR/metallb-iprange.yaml)&

# override metallb ip range for mcp-migration cluster
# 이 클러스터는 192.168.2.0/24의 .230~.250 풀 배정 (루트 CLAUDE.md IP 배정표).
# remote metallb-iprange.yaml applies 192.168.1.11-99 (wrong subnet here) -> override + delete it.
(sleep 660 && kubectl apply -f - <<'METALLB_EOF'
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default
  namespace: metallb-system
spec:
  addresses:
  - 192.168.2.230-192.168.2.250
METALLB_EOF
)&
# remove the conflicting k8s-svc-pool (192.168.1.11-99) left by metallb-iprange.yaml
(sleep 720 && kubectl delete ipaddresspool k8s-svc-pool -n metallb-system --ignore-not-found)&

# metrics server v0.8.0 - insecure mode (측정 중 노드/파드 리소스 관찰용)
kubectl apply -f $EXTRA_PKGS_ADDR/metrics-server-notls-v0.8.0.yaml

# NOTE(mcp-migration): agents-md 대비 제외한 것들과 이유
# - nginx gateway fabric: 측정 경로 (b)는 격리 캠페인으로 그때 설치 (섞임 방지)
# - NFS/csi-driver/storageclass: 이 연구는 PV 불필요
# - audit: 에이전트 채점 없음
