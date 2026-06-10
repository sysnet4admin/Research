#!/usr/bin/env bash
# 공용 substrate 계약. 각 install 스크립트가 source 한다.
# bash 3.2 호환(연관배열 미사용) — macOS 호스트에서 실행 가능.

set -euo pipefail

# kubectl/helm 대상 컨텍스트 (CLAUDE.md: 항상 --context 명시)
KUBE_CONTEXT="${KUBE_CONTEXT:-gateway-PoC}"

# Gateway API target (SCORING.md 9장)
GWAPI_VERSION="v1.4.1"
GWAPI_CHANNEL="experimental"   # standard 상위집합

# 헬퍼: 항상 컨텍스트 명시
kc() { kubectl --context "$KUBE_CONTEXT" "$@"; }
hc() { helm --kube-context "$KUBE_CONTEXT" "$@"; }

export KUBE_CONTEXT GWAPI_VERSION GWAPI_CHANNEL
export -f kc hc

# 구현체별 메타(참고용 표는 README.md). GatewayClass 이름:
#   nginx eg istio cilium kong traefik kgateway
