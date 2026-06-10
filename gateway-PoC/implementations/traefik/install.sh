#!/usr/bin/env bash
# Traefik v3.6.x (Gateway API v1.4). 최신 v3.7은 v1.5용이라 image.tag 핀.
# 주의: Traefik은 프록시용 LB Service 1개를 만들고 Gateway가 entryPoint를 공유한다.
# Gateway listener 포트가 web(80)/websecure(443) entryPoint와 일치해야 한다.

set -euo pipefail
source "$(dirname "$0")/../config.sh"

TRAEFIK_IMAGE_TAG="v3.6.17"   # 설치 직전 3.6 최신 패치 확인

echo "==> Traefik ${TRAEFIK_IMAGE_TAG} 설치 (ns traefik, Gateway provider + experimental 채널)"
helm repo add traefik https://traefik.github.io/charts >/dev/null 2>&1 || true
helm repo update traefik >/dev/null

hc install traefik traefik/traefik \
  --namespace traefik --create-namespace --wait \
  --set image.tag="${TRAEFIK_IMAGE_TAG}" \
  --set providers.kubernetesGateway.enabled=true \
  --set providers.kubernetesGateway.experimentalChannel=true

echo "==> GatewayClass 'traefik' 확인/생성"
kc apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: traefik
spec:
  controllerName: traefik.io/gateway-controller
EOF
kc get gatewayclass traefik
