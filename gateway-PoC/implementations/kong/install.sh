#!/usr/bin/env bash
# Kong Gateway Operator (KGO) 2.1.x managed gateway 경로 (legacy KIC 아님).
# 2.1.x부터 Gateway API v1.4 지원(2.0.x 미지원). controllerName konghq.com/gateway-operator.

set -euo pipefail
source "$(dirname "$0")/../config.sh"

echo "==> Kong Gateway Operator (image.tag 2.1) 설치 (ns kong-system)"
helm repo add kong https://charts.konghq.com >/dev/null 2>&1 || true
helm repo update kong >/dev/null

hc upgrade --install kong-operator kong/kong-operator -n kong-system \
  --create-namespace --set image.tag=2.1 --wait

echo "==> managed gateway 리소스: GatewayConfiguration + GatewayClass 'kong'"
# Gateway(데이터플레인 트리거)는 측정 단계에서 생성. 여기선 클래스/설정만 준비.
kc create namespace kong --dry-run=client -o yaml | kc apply -f -
kc apply -f - <<'EOF'
apiVersion: gateway-operator.konghq.com/v2beta1
kind: GatewayConfiguration
metadata:
  name: kong-configuration
  namespace: kong
spec:
  dataPlaneOptions:
    deployment:
      podTemplateSpec:
        spec:
          containers:
          # community OSS Kong(=Kong/kong 리포 최신, 3.9.1이 마지막). enterprise
          # kong/kong-gateway:3.14는 KGO 2.1.x 기본값(3.13)보다 새 버전이라
          # all-or-nothing config 푸시가 400으로 거부됨. OSS 벤더비종속 기준에도
          # community 이미지가 정답. KGO 2.1.x 공식 OSS 샘플도 kong:3.9 사용.
          - name: proxy
            image: kong:3.9.1
            # router_flavor=expressions: query-param/method 매칭 등 Gateway API 기능에 필요.
            # OSS 디폴트 traditional_compatible은 query-param 미지원이라, Kong 권장 설정인
            # expressions로 측정한다(2026-06-10 공정성 재측정). 공식 conformance도 expressions
            # 모드에서 query-param-matching supported.
            env:
            - name: KONG_ROUTER_FLAVOR
              value: expressions
---
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: kong
spec:
  controllerName: konghq.com/gateway-operator
  parametersRef:
    group: gateway-operator.konghq.com
    kind: GatewayConfiguration
    name: kong-configuration
    namespace: kong
EOF
kc get gatewayclass kong
