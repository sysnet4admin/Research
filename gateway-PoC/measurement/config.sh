#!/usr/bin/env bash
# 측정 단계 공용 설정. bash 3.2 호환.
# 측정은 컨트롤러(install 단계)가 준비된 클러스터에서 픽스처(Gateway/route/백엔드)를
# 배포하고 rubric.yaml에 정의된 테스트를 돌려 round-N.json 을 만든다.

set -euo pipefail

KUBE_CONTEXT="${KUBE_CONTEXT:-gateway-PoC}"
kc() { kubectl --context "$KUBE_CONTEXT" "$@"; }

# 측정 대상 7종 (SCORING.md 10장). 환경변수로 부분 실행 가능(디버깅).
IMPLS="${IMPLS:-nginx envoy istio cilium kong traefik kgateway}"

# impl → GatewayClass 이름 (install README substrate 계약)
gwclass_of() {
  case "$1" in
    nginx) echo nginx ;;
    envoy) echo eg ;;
    istio) echo istio ;;
    cilium) echo cilium ;;
    kong) echo kong ;;
    traefik) echo traefik ;;
    kgateway) echo kgateway ;;
    *) echo "" ;;
  esac
}

# impl → 버전(리포트 표기용; 설치 버전과 일치시킬 것)
version_of() {
  case "$1" in
    nginx) echo "2.4.2" ;;
    envoy) echo "v1.7.3" ;;
    istio) echo "1.30.0" ;;
    cilium) echo "1.19.4" ;;
    kong) echo "KGO 2.1" ;;
    traefik) echo "v3.6.17" ;;
    kgateway) echo "v2.2.2" ;;
    *) echo "?" ;;
  esac
}

# 테스트 네임스페이스 / 도메인 / 백엔드 토큰 (하드코딩 제거: 토큰을 변수로)
TEST_NS="gwtest"
BACKEND2_NS="gwtest-backend2"      # cross-namespace 테스트용
BACKEND_V1_TOKEN="backend-v1"
BACKEND_V2_TOKEN="backend-v2"

# 도메인 (HTTPRoute hostnames)
DOMAIN_V1="v1.example.com"
DOMAIN_V2="v2.example.com"
DOMAIN_CANARY="canary.example.com"
DOMAIN_REDIRECT="redirect.example.com"   # https-redirect 전용(HTTP 서빙과 분리)

# 산출 경로
ROUND="${ROUND:-1}"
RESULTS_DIR="${RESULTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/results/rounds}"

# Gateway API target (검증용)
GWAPI_VERSION="v1.4"
GWAPI_CHANNEL="experimental"

export KUBE_CONTEXT IMPLS TEST_NS BACKEND2_NS BACKEND_V1_TOKEN BACKEND_V2_TOKEN
export DOMAIN_V1 DOMAIN_V2 DOMAIN_CANARY DOMAIN_REDIRECT ROUND RESULTS_DIR GWAPI_VERSION GWAPI_CHANNEL
export -f kc gwclass_of version_of
