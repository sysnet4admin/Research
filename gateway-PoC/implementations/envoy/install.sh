#!/usr/bin/env bash
# Envoy Gateway v1.7.x (Gateway API 1.4.1). 최신 v1.8은 v1.5용이라 회피.
# 차트가 Gateway API CRD를 번들하므로 --skip-crds 필수.

set -euo pipefail
source "$(dirname "$0")/../config.sh"

EG_VERSION="v1.7.3"   # 설치 직전 1.7 최신 패치 확인

echo "==> Envoy Gateway ${EG_VERSION} 설치 (ns envoy-gateway-system, --skip-crds)"
hc install eg oci://docker.io/envoyproxy/gateway-helm \
  --version "${EG_VERSION}" \
  -n envoy-gateway-system --create-namespace --skip-crds --wait

echo "==> 벤더 정책 CRD 설치 (gateway.envoyproxy.io_* 만, Gateway API v1.4 CRD 보존)"
# --skip-crds 로 빠진 벤더 정책 CRD(BackendTrafficPolicy/SecurityPolicy/ClientTrafficPolicy/
# EnvoyExtensionPolicy/EnvoyPatchPolicy 등)를 매트릭스·auth 측정용으로 설치한다.
# 차트의 crds/generated/ 만 적용(crds/gatewayapi-crds.yaml 제외 → 사전설치 v1.4 experimental CRD 보존).
EG_CRD_TMP="$(mktemp -d)"
hc pull oci://docker.io/envoyproxy/gateway-helm --version "${EG_VERSION}" \
  --untar --untardir "${EG_CRD_TMP}" >/dev/null
kc apply --server-side -f "${EG_CRD_TMP}/gateway-helm/crds/generated/"
rm -rf "${EG_CRD_TMP}"
# 컨트롤러가 새 CRD를 watch 하도록 재시작
kc -n envoy-gateway-system rollout restart deploy/envoy-gateway >/dev/null 2>&1 || true

echo "==> GatewayClass 'eg' 생성 (차트가 자동 생성 안 함)"
kc apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
EOF
kc get gatewayclass eg
