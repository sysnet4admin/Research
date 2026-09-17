#!/usr/bin/env bash
# 무인 창 사전 점검. 하나라도 실패하면 비0 종료라 캠페인이 기동하지 않는다.
set -u
CTX="aaif-benchmark"
PY="$HOME/.venvs/mcpbench/bin/python"
fail=0
chk() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then echo "[OK]   $d"; else echo "[FAIL] $d"; fail=1; fi; }
chk "AC 전원" bash -c "pmset -g batt | grep -q 'AC Power'"
chk "venv httpx" "$PY" -c "import httpx"
chk "노드 3대 Ready" bash -c "[ \$(kubectl --context $CTX get nodes --no-headers 2>/dev/null | grep -c ' Ready') -eq 3 ]"
chk "Agent Router 컨트롤러" bash -c "kubectl --context $CTX -n envoy-ai-gateway-system get deploy ai-gateway-controller -o jsonpath='{.status.readyReplicas}' | grep -q 1"
chk "Envoy Gateway 컨트롤러" bash -c "kubectl --context $CTX -n envoy-gateway-system get deploy envoy-gateway -o jsonpath='{.status.readyReplicas}' | grep -q 1"
chk "ar-gw 주소" bash -c "[ -n \"\$(kubectl --context $CTX -n mcp-pilot get gateway ar-gw -o jsonpath='{.status.addresses[0].value}')\" ]"
chk "백엔드 mcp-b" bash -c "kubectl --context $CTX -n mcp-pilot get deploy mcp-b -o jsonpath='{.status.readyReplicas}' | grep -q 1"
chk "백엔드 reflect" bash -c "kubectl --context $CTX -n mcp-pilot get deploy reflect -o jsonpath='{.status.readyReplicas}' | grep -q 1"
chk "간섭 프로세스 없음: hugo" bash -c "! pgrep -f 'hugo server'"
chk "간섭 프로세스 없음: colima" bash -c "! pgrep -f 'colima.*qemu'"
chk "디스크 여유 20GB+" bash -c "[ \$(df -g / | tail -1 | awk '{print \$4}') -ge 20 ]"
[ "$fail" -ne 0 ] && { echo "== 사전 점검 실패. 기동 금지 =="; exit 1; }
echo "== 사전 점검 전부 통과 =="
