#!/usr/bin/env bash
# kgateway 2.2.2 (Gateway API 1.2-1.4, arm64는 2.2+). kgateway GatewayClass 자동.
# Gateway API CRD는 00-... 가 설치 → kgateway-crds 차트와 standard-install.yaml 생략.

set -euo pipefail
source "$(dirname "$0")/../config.sh"

KGW_VERSION="v2.2.2"

echo "==> kgateway ${KGW_VERSION} 설치 (ns kgateway-system)"
hc upgrade -i -n kgateway-system --create-namespace kgateway \
  oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
  --version "${KGW_VERSION}" --wait

echo "==> kgateway 벤더 정책 CRD 설치 (kgateway-crds 차트, gateway.kgateway.dev 전용)"
# main 차트는 kgateway 정책 CRD를 깔지 않는다. 매트릭스(rate-limit/body-size)·auth(JWT/extAuth)
# 측정에 필요한 TrafficPolicy/GatewayExtension/BackendConfigPolicy 등은 별도 kgateway-crds 차트에 있다.
# 이 차트는 gateway.kgateway.dev 그룹 전용이라 Gateway API CRD(사전설치 v1.4)를 건드리지 않는다.
GWAPI_BEFORE="$(kc get crd httproutes.gateway.networking.k8s.io \
  -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}' 2>/dev/null || true)"
hc upgrade -i -n kgateway-system kgateway-crds \
  oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds \
  --version "${KGW_VERSION}" --wait
# 방어: Gateway API CRD 번들버전이 변하지 않았는지 확인(혹시 차트가 GW API CRD를 건드렸으면 중단)
GWAPI_AFTER="$(kc get crd httproutes.gateway.networking.k8s.io \
  -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}' 2>/dev/null || true)"
if [ -n "${GWAPI_BEFORE}" ] && [ "${GWAPI_BEFORE}" != "${GWAPI_AFTER}" ]; then
  echo "[abort] kgateway-crds 가 Gateway API CRD 를 변경함(${GWAPI_BEFORE} -> ${GWAPI_AFTER})" >&2
  exit 1
fi
kc -n kgateway-system rollout restart deploy/kgateway >/dev/null 2>&1 || true

echo "==> GatewayClass 'kgateway' 확인 (chart 자동, controllerName kgateway.dev/kgateway)"
kc get gatewayclass kgateway 2>/dev/null || echo "(자동 생성 대기 중)"
