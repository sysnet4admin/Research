#!/usr/bin/env bash
# 경로 (c) 캠페인 종료: agentgateway와 Gateway API CRD 전부 제거 (격리 복원)
# aaif-benchmark용 사본 (원본: mcp-migration studies k8s/agentgateway/. 컨텍스트만 교체)
set -euo pipefail

CTX="aaif-benchmark"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

kubectl --context $CTX delete -f "$DIR/../../mcp-migration/studies/stateless-scaleout/k8s/agentgateway/gateway.yaml" --ignore-not-found
helm --kube-context $CTX uninstall agentgateway -n agentgateway-system 2>/dev/null || true
helm --kube-context $CTX uninstall agentgateway-crds -n agentgateway-system 2>/dev/null || true
kubectl --context $CTX delete namespace agentgateway-system --ignore-not-found
kubectl --context $CTX delete \
  -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml \
  --ignore-not-found
echo "==> agentgateway 캠페인 제거 완료"
