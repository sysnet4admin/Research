#!/usr/bin/env bash

# avoid 'dpkg-reconfigure: unable to re-open stdin: No file or directory'
export DEBIAN_FRONTEND=noninteractive

# swapoff -a to disable swapping
swapoff -a
# sed to comment the swap partition in /etc/fstab (Rmv blank)
sed -i.bak -r 's/(.+swap.+)/#\1/' /etc/fstab

# add kubernetes repo
curl \
  -fsSL https://pkgs.k8s.io/core:/stable:/v$2/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo \
  "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/v$2/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list

# add docker-ce repo with containerd
curl -fsSL \
  https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) \
  signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

# packets traversing the bridge are processed by iptables for filtering
echo 1 > /proc/sys/net/ipv4/ip_forward
# enable br_filter for iptables
modprobe br_netfilter
modprobe overlay
# 재부팅(스냅샷 halt/up 포함) 후에도 유지되게 영속화
# (미영속 시 스냅샷 복원 후 Flannel 등이 br_netfilter 부재로 CrashLoop - 파일럿에서 실측)
printf 'br_netfilter\noverlay\n' > /etc/modules-load.d/k8s.conf
printf 'net.bridge.bridge-nf-call-iptables=1\nnet.bridge.bridge-nf-call-ip6tables=1\nnet.ipv4.ip_forward=1\n' > /etc/sysctl.d/99-k8s.conf
sysctl --system >/dev/null

# local small dns & vagrant cannot parse and delivery shell code.
# cni-benchmark 클러스터는 192.168.2.0/24의 .50번대
echo "127.0.0.1 localhost" > /etc/hosts
echo "192.168.2.50 cp-k8s" >> /etc/hosts
for (( i=1; i<=$1; i++  )); do echo "192.168.2.5$i w$i-k8s" >> /etc/hosts; done
