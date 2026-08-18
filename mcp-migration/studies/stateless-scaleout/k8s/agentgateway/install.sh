#!/usr/bin/env bash
# 경로 (c) agentgateway 격리 캠페인: 설치.
# gateway-PoC 방식: 캠페인 시작 시 설치, 종료 시 uninstall.sh로 전부 제거.
# 버전 고정: Gateway API CRD v1.5.0 standard, agentgateway v1.3.1 (현행 스펙).
# 신 스펙 네이티브 측정 시 v1.4.0-alpha.x로 교체 (버전을 결과에 기록).
set -euo pipefail

CTX="mcp-migration"
AGW_VER="${AGW_VER:-v1.3.1}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Gateway API CRDs v1.5.0 (standard)"
kubectl --context $CTX apply --server-side --force-conflicts \
  -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml

echo "==> agentgateway CRDs $AGW_VER"
helm --kube-context $CTX upgrade -i agentgateway-crds oci://cr.agentgateway.dev/charts/agentgateway-crds \
  --create-namespace --namespace agentgateway-system --version "$AGW_VER"

echo "==> agentgateway control plane $AGW_VER"
helm --kube-context $CTX upgrade -i agentgateway oci://cr.agentgateway.dev/charts/agentgateway \
  --namespace agentgateway-system --version "$AGW_VER" --wait

echo "==> Gateway (agentgateway class) + backends + routes"
kubectl --context $CTX apply -f "$DIR/gateway.yaml"

echo "==> Gateway 주소 대기 (MetalLB)"
for i in $(seq 1 30); do
  ADDR=$(kubectl --context $CTX get gateway agentgateway-proxy -n agentgateway-system -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)
  [ -n "$ADDR" ] && break
  sleep 5
done
echo "Gateway address: ${ADDR:-NOT_ASSIGNED}"
kubectl --context $CTX get pods -n agentgateway-system
