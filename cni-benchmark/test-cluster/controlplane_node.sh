#!/usr/bin/env bash

# init kubernetes (w/ containerd). CNI는 여기서 설치하지 않는다 (조건별 설치).
kubeadm init --token 123456.1234567890123456 --token-ttl 0 \
             --pod-network-cidr=172.16.0.0/16 --apiserver-advertise-address=192.168.2.50 \
             --cri-socket=unix:///run/containerd/containerd.sock

# config for master node only
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# NOTE(cni-benchmark): CNI 설치 없음. 노드는 NotReady로 남는 것이 정상.
# 조건별 CNI는 studies/standing-cost/conditions/<ID>.sh 가 설치한다.

# kubectl completion on bash-completion dir
kubectl completion bash >/etc/bash_completion.d/kubectl

# alias kubectl to k
echo 'alias k=kubectl'               >> ~/.bashrc
echo "alias kg='kubectl get'"        >> ~/.bashrc
echo "alias ka='kubectl apply -f'"   >> ~/.bashrc
echo "alias kd='kubectl delete -f'"  >> ~/.bashrc
echo 'complete -F __start_kubectl k' >> ~/.bashrc

# extended k8s certifications all
git clone https://github.com/yuyicai/update-kube-cert.git /tmp/update-kube-cert
chmod 755 /tmp/update-kube-cert/update-kubeadm-cert.sh
/tmp/update-kube-cert/update-kubeadm-cert.sh all --cri containerd
rm -rf /tmp/update-kube-cert
echo "Wait 10 seconds for restarting the Control-Plane Node..." ; sleep 10
