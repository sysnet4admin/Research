#!/usr/bin/env bash
# NGINX Gateway Fabric 2.4.2 (Gateway API 1.4.1). 최신 2.6.x는 v1.5용이라 회피.

set -euo pipefail
source "$(dirname "$0")/../config.sh"

NGF_VERSION="2.4.2"

echo "==> NGINX Gateway Fabric ${NGF_VERSION} 설치 (ns nginx-gateway)"
# Gateway API CRD는 00-gateway-api-crds.sh 가 이미 설치(차트가 안 깖) → 선행단계 생략
hc install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
  --version "${NGF_VERSION}" \
  --namespace nginx-gateway --create-namespace --wait \
  --set nginxGateway.gwAPIExperimentalFeatures.enable=true

echo "==> GatewayClass 'nginx' 확인 (chart 자동 생성)"
kc get gatewayclass nginx 2>/dev/null || echo "(자동 생성 대기 중)"
