#!/usr/bin/env bash

# cni-benchmark: 추가 구성 최소화 원칙.
# - MetalLB 없음 (스피커 파드가 측정 잡음)
# - metrics-server 없음 (수집은 kubelet cadvisor 프록시 직접 폴링)
# - NFS/스토리지 없음
# - helm만 설치 (Cilium/Calico operator 조건 설치용)

EXTRA_PKGS_ADDR="https://raw.githubusercontent.com/sysnet4admin/IaC/main/k8s/extra-pkgs/v1.35"

curl $EXTRA_PKGS_ADDR/get_helm_v4.0.4.sh | bash
helm completion bash > /etc/bash_completion.d/helm
echo 'alias h=helm' >> ~/.bashrc
echo 'complete -F __start_helm h' >> ~/.bashrc

# bpftool (eBPF map 메모리 수집용)
export DEBIAN_FRONTEND=noninteractive
apt-get install -y linux-tools-common "linux-tools-$(uname -r)" 2>/dev/null || \
  apt-get install -y linux-tools-generic 2>/dev/null || true
which bpftool || echo "WARN: bpftool 미설치 (수집기가 대체 경로 사용)"
