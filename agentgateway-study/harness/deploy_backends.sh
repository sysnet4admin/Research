#!/usr/bin/env bash
# aaif-benchmark 클러스터에 MCP 백엔드 배포.
# mcp-migration studies/stateless-scaleout/k8s/deploy.sh의 사본을 컨텍스트만
# 바꾼 것(원본 무수정 원칙, REMEASURE.md). yaml과 서버 코드는 원본 재사용.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
REPO="$(cd "$STUDY/.." && pwd)"
K8SDIR="$REPO/mcp-migration/studies/stateless-scaleout/k8s"
CTX="aaif-benchmark"

kubectl --context "$CTX" create namespace mcp-pilot --dry-run=client -o yaml \
  | kubectl --context "$CTX" apply -f -

kubectl --context "$CTX" create configmap b-server-code \
  --from-file=server.py="$K8SDIR/../b-server/server.py" \
  -n mcp-pilot --dry-run=client -o yaml \
  | kubectl --context "$CTX" apply -f -

kubectl --context "$CTX" apply -f "$K8SDIR/redis.yaml"
kubectl --context "$CTX" apply -f "$K8SDIR/a-server.yaml"
kubectl --context "$CTX" apply -f "$K8SDIR/b-server.yaml"

echo "==> rollout 대기"
kubectl --context "$CTX" -n mcp-pilot rollout status deploy/mcp-a --timeout=300s
kubectl --context "$CTX" -n mcp-pilot rollout status deploy/mcp-b --timeout=300s

echo "==> LB IP"
kubectl --context "$CTX" -n mcp-pilot get svc -o wide
