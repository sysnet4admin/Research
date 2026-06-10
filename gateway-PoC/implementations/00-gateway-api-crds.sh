#!/usr/bin/env bash
# Gateway API v1.4.1 experimental 채널 CRD 설치 (공용 단일 소스).
# 구현체들은 자체 CRD를 다시 깔지 않는다(README.md CRD 처리 참조).

set -euo pipefail
source "$(dirname "$0")/config.sh"

echo "==> Gateway API ${GWAPI_VERSION} ${GWAPI_CHANNEL} 채널 CRD 설치"
# --server-side: HTTPRoute CRD가 256KB 어노테이션 한계를 넘어 client-side apply 실패.
# server-side apply는 last-applied 어노테이션을 안 써서 한계를 회피한다.
kc apply --server-side --force-conflicts -f \
  "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GWAPI_VERSION}/${GWAPI_CHANNEL}-install.yaml"

echo "==> CRD 확인"
kc get crd | grep -E "gateway.networking.k8s.io" || true
echo "==> 완료"
