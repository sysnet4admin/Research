#!/usr/bin/env bash
# 파일럿 워크로드 배포. 항상 --context mcp-migration 명시.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX="mcp-migration"

kubectl --context "$CTX" create namespace mcp-pilot --dry-run=client -o yaml \
  | kubectl --context "$CTX" apply -f -

kubectl --context "$CTX" create configmap b-server-code \
  --from-file=server.py="$DIR/../b-server/server.py" \
  -n mcp-pilot --dry-run=client -o yaml \
  | kubectl --context "$CTX" apply -f -

kubectl --context "$CTX" apply -f "$DIR/redis.yaml"
kubectl --context "$CTX" apply -f "$DIR/a-server.yaml"
kubectl --context "$CTX" apply -f "$DIR/b-server.yaml"

echo "==> rollout 대기"
kubectl --context "$CTX" -n mcp-pilot rollout status deploy/mcp-a --timeout=300s
kubectl --context "$CTX" -n mcp-pilot rollout status deploy/mcp-b --timeout=300s

echo "==> LB IP"
kubectl --context "$CTX" -n mcp-pilot get svc -o wide
