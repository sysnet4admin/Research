#!/usr/bin/env bash

# init kubernetes (w/ containerd)
# --skip-phases=addon/kube-proxy: kube-proxy is replaced by Cilium eBPF below.
kubeadm init --token 123456.1234567890123456 --token-ttl 0 \
             --pod-network-cidr=172.16.0.0/16 --apiserver-advertise-address=192.168.1.150 \
             --cri-socket=unix:///run/containerd/containerd.sock \
             --skip-phases=addon/kube-proxy

# config for master node only
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# helm (required for Cilium install)
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# CNI: Cilium v1.19.4 in kube-proxy replacement mode (eBPF).
# k8sServiceHost/Port point Cilium at the API server directly since
# kube-proxy is absent. gatewayAPI is intentionally NOT enabled here;
# Gateway API CRDs + per-implementation enablement happen in the
# implementation-install step (see test-cluster/README.md).
CILIUM_V="1.19.4"
helm repo add cilium https://helm.cilium.io/
helm repo update
helm install cilium cilium/cilium --version "$CILIUM_V" \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=192.168.1.150 \
  --set k8sServicePort=6443 \
  --set ipam.mode=kubernetes \
  --set l2announcements.enabled=false

# wait for Cilium to be ready before declaring the CP node done
kubectl -n kube-system rollout status ds/cilium --timeout=300s || true

# kubectl completion on bash-completion dir
kubectl completion bash >/etc/bash_completion.d/kubectl

# alias kubectl to k
echo 'alias k=kubectl'               >> ~/.bashrc
echo "alias kg='kubectl get'"        >> ~/.bashrc
echo "alias ka='kubectl apply -f'"   >> ~/.bashrc
echo "alias kd='kubectl delete -f'"  >> ~/.bashrc
echo 'complete -F __start_kubectl k' >> ~/.bashrc

# helm completion + alias
helm completion bash > /etc/bash_completion.d/helm
echo 'alias h=helm' >> ~/.bashrc
echo 'complete -F __start_helm h' >> ~/.bashrc

# extended k8s certifications all
git clone https://github.com/yuyicai/update-kube-cert.git /tmp/update-kube-cert
chmod 755 /tmp/update-kube-cert/update-kubeadm-cert.sh
/tmp/update-kube-cert/update-kubeadm-cert.sh all --cri containerd
rm -rf /tmp/update-kube-cert
echo "Wait 10 seconds for restarting the Control-Plane Node..." ; sleep 10
