#!/usr/bin/env bash
# rv 재측정 사전 점검 게이트. 하나라도 실패하면 비0 종료(체인이 기동을 거부).
# 근거: 8/31 사고 3건(venv 소실, 배터리 절전, 캠페인 중 렌더 부하).
set -u
CTX="aaif-benchmark"
PY="$HOME/.venvs/mcpbench/bin/python"
fail=0
chk() { # chk <설명> <명령...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "[OK]   $desc"; else echo "[FAIL] $desc"; fail=1; fi
}
chk "AC 전원" bash -c "pmset -g batt | grep -q 'AC Power'"
chk "venv httpx" "$PY" -c "import httpx"
chk "간섭 프로세스 없음: Keynote" bash -c "! pgrep -x Keynote"
chk "간섭 프로세스 없음: PowerPoint" bash -c "! pgrep -f 'Microsoft PowerPoint'"
chk "간섭 프로세스 없음: hugo" bash -c "! pgrep -f 'hugo server'"
chk "간섭 프로세스 없음: colima VM" bash -c "! pgrep -f 'colima.*qemu\|lima.*ha.sock' && ! colima status 2>&1 | grep -q 'colima is running'"
chk "VM 3대 실행 중" bash -c "[ \$(VBoxManage list runningvms | grep -c aaifbm) -eq 3 ]"
chk "노드 3대 Ready" bash -c "[ \$(kubectl --context $CTX get nodes --no-headers 2>/dev/null | grep -c ' Ready') -eq 3 ]"
chk "디스크 여유 30GB+" bash -c "[ \$(df -g / | tail -1 | awk '{print \$4}') -ge 30 ]"
if [ "$fail" -ne 0 ]; then echo "== 사전 점검 실패. 기동 금지 =="; exit 1; fi
echo "== 사전 점검 전부 통과 =="
