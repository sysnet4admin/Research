#!/usr/bin/env bash
# Cilium Gateway: 기존 CNI(1.19.4)에 Gateway API 지원 활성화.
# 별도 설치가 아니라 helm upgrade --reuse-values 로 플래그만 켠다.

set -euo pipefail
source "$(dirname "$0")/../config.sh"

echo "==> Cilium Gateway API 활성화 (1.19.4 CNI 재구성)"
helm repo add cilium https://helm.cilium.io/ >/dev/null 2>&1 || true
helm repo update cilium >/dev/null

hc upgrade cilium cilium/cilium --namespace kube-system --reuse-values \
  --set kubeProxyReplacement=true \
  --set gatewayAPI.enabled=true \
  --set l7Proxy=true

echo "==> operator/agent 재시작"
kc -n kube-system rollout restart deployment/cilium-operator
kc -n kube-system rollout restart ds/cilium
kc -n kube-system rollout status ds/cilium --timeout=300s || true

echo "==> GatewayClass 'cilium' 확인 (controllerName io.cilium/gateway-controller)"
kc get gatewayclass cilium 2>/dev/null || echo "(아직 생성 안 됨 - operator 기동 후 재확인)"
