#!/usr/bin/env bash
# 오케스트레이터: Gateway API CRD → 7개 컨트롤러 순차 설치.
# 완료 후 test-cluster/snapshot.sh 로 baseline 스냅샷 권장.

set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh

echo "### context: ${KUBE_CONTEXT}, Gateway API ${GWAPI_VERSION}/${GWAPI_CHANNEL}"

./00-gateway-api-crds.sh

for impl in cilium nginx envoy istio traefik kgateway kong; do
  echo ""
  echo "============================================================"
  echo "### install: ${impl}"
  echo "============================================================"
  ./"${impl}"/install.sh
done

echo ""
echo "### 전체 GatewayClass 상태"
kc get gatewayclass
echo ""
echo "### 완료. test-cluster/snapshot.sh 로 baseline 스냅샷을 찍으세요."
