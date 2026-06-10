#!/usr/bin/env bash
# Istio 1.30.x (1.28+ = Gateway API v1.4). helm base+istiod. istio GatewayClass 자동.

set -euo pipefail
source "$(dirname "$0")/../config.sh"

ISTIO_VERSION="1.30.0"

echo "==> Istio ${ISTIO_VERSION} 설치 (helm base+istiod, ns istio-system)"
helm repo add istio https://istio-release.storage.googleapis.com/charts >/dev/null 2>&1 || true
helm repo update istio >/dev/null

hc install istio-base istio/base -n istio-system --create-namespace \
  --version "${ISTIO_VERSION}" --set defaultRevision=default --wait
# PILOT_ENABLE_ALPHA_GATEWAY_API=true: v1.4 experimental의 TLSRoute(alpha)를 istiod가
# watch하게 한다. 이 플래그 없으면 TLSRoute status가 안 달려 tls-passthrough가 미측정처럼
# 보인다. 단 2026-06-10 재측정 결과 플래그를 켜도 istio 1.30.0은 TLSRoute passthrough를
# 프로그래밍하지 않아 tls-passthrough는 여전히 미지원(known issue istio #47366). istio의
# TLSRoute는 Terminate 모드만 공식 conformant(v1.5.1)이고 passthrough는 미검증.
hc install istiod istio/istiod -n istio-system \
  --version "${ISTIO_VERSION}" --set pilot.env.PILOT_ENABLE_ALPHA_GATEWAY_API=true --wait

echo "==> GatewayClass 'istio' 확인 (istiod 자동 등록, controllerName istio.io/gateway-controller)"
kc get gatewayclass istio 2>/dev/null || echo "(자동 등록 대기 중)"
