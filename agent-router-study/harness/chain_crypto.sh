#!/usr/bin/env bash
# 기준 회차가 끝나면 반복 횟수를 낮추고 같은 회차를 한 번 더 돈다.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
CTX="aaif-benchmark"
NS="envoy-gateway-system"
SEL='gateway.envoyproxy.io/owning-gateway-name=ar-gw'
export URL="http://192.168.2.106/mcp"

echo "[$(date +%H:%M:%S)] 기준 회차 종료 대기"
while pgrep -f "crypto_cost.sh 100000" >/dev/null; do sleep 20; done
echo "[$(date +%H:%M:%S)] 기준 회차 끝"

echo "[$(date +%H:%M:%S)] 반복 횟수를 1000으로 내린다"
helm --kube-context "$CTX" upgrade aieg oci://docker.io/envoyproxy/ai-gateway-helm \
  --version v1.1.0 -n envoy-ai-gateway-system --reuse-values \
  --set controller.mcp.sessionEncryption.iterations=1000 --wait --timeout 5m \
  || { echo "helm 실패"; exit 1; }

# 컨트롤러가 프록시를 다시 프로그래밍할 때까지 기다린다. 사이드카 인자가 실제로
# 바뀌었는지 확인하기 전에는 재지 않는다.
echo "[$(date +%H:%M:%S)] 사이드카 인자 반영 대기"
DEADLINE=$(( $(date +%s) + 600 ))
while :; do
  A=$(kubectl --context "$CTX" -n "$NS" get pods -l "$SEL" \
      -o jsonpath='{.items[0].spec.initContainers[?(@.name=="ai-gateway-extproc")].args}' 2>/dev/null)
  R=$(kubectl --context "$CTX" -n "$NS" get pods -l "$SEL" --no-headers 2>/dev/null | grep -c '3/3 *Running')
  case "$(echo "$A" | tr -d "\"[] ")" in *mcpSessionEncryptionIterations1000*) [ "$R" -ge 1 ] && break ;; esac
  [ "$(date +%s)" -gt "$DEADLINE" ] && { echo "반영되지 않았다. 중단."; exit 1; }
  sleep 15
done
echo "[$(date +%H:%M:%S)] 반영됨. 60초 정착 대기"
sleep 60

"$DIR/crypto_cost.sh" 1000
echo "[$(date +%H:%M:%S)] 두 회차 끝"
"$HOME/.venvs/mcpbench/bin/python" "$DIR/crypto_report.py" 100000 1000
