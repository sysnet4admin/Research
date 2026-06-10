#!/usr/bin/env bash
# CP 노드에서 실행(KUBECONFIG 설정). 워커가 조인해 스케줄 가능 노드가 생긴 뒤
# up.sh 가 호출한다. tainted CP 단독 노드에서는 MetalLB controller가 Pending이라
# CP 프로비저닝 중 적용하면 실패한다(과거 버그). 그래서 노드 Ready 후로 분리.

set -euo pipefail

echo "==> MetalLB v0.15.3 적용"
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml

echo "==> controller Ready 대기"
kubectl -n metallb-system rollout status deploy/controller --timeout=300s

echo "==> gateway-pool(.11-17) + L2Advertisement 적용"
# Cilium이 webhook ClusterIP를 eBPF(socket-LB)에 프로그래밍하기까지 수초 지연이 있어
# rollout 직후 적용하면 'no route to host'가 날 수 있다. 재시도로 흡수한다.
APPLY_POOL() {
  kubectl apply -f - <<'EOF'
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: gateway-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.11-192.168.1.17
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: gateway-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - gateway-pool
EOF
}
for i in $(seq 1 20); do
  if APPLY_POOL; then echo "==> MetalLB 적용 완료"; break; fi
  echo "   재시도 $i (webhook 프로그래밍 대기)..."; sleep 10
done
