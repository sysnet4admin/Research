#!/usr/bin/env bash
# F1n: F1 + kube-proxy nftables 모드 (모드 차이 순수 분리, 1.33 GA / 1.36 기본은 iptables)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# F1 설치
"$COND_DIR/F1.sh"

echo "==> kube-proxy 모드 iptables -> nftables 전환"
k -n kube-system get cm kube-proxy -o yaml \
  | sed 's/mode: ""/mode: "nftables"/; s/mode: iptables/mode: "nftables"/' \
  | k apply -f -
k -n kube-system rollout restart ds/kube-proxy
k -n kube-system rollout status ds/kube-proxy --timeout=180s

# 모드 적용 확인 (kube-proxy 로그에 nftables 표기)
sleep 5
POD=$(k -n kube-system get pods -l k8s-app=kube-proxy -o name | head -1)
k -n kube-system logs "$POD" 2>/dev/null | grep -qi "nftables" \
  && echo "==> nftables 모드 확인" \
  || echo "WARN: 로그에서 nftables 미확인 (수동 검증 필요)"

smoke_test
echo "F1n ready"
