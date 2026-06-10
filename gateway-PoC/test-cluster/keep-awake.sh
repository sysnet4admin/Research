#!/usr/bin/env bash
# gateway-poc VM이 running인 동안에만 호스트 시스템 절전을 막는다.
# (호스트 절전이 VirtualBox VM을 'paused due to host power management' 상태로 만들어
#  halt/측정이 깨지는 사고를 방지. 2026-06-05 halt 시 실제 발생.)
# 디스플레이 절전은 막지 않음(-is = idle + AC 시스템 절전만). VM이 전부 halt되면 자동 종료.
#
# 사용: vagrant up 후 한 번 실행 →  ./keep-awake.sh
# 중지: 수동 중지하려면  pkill -f GWPOC_CAFFEINATE   (halt하면 자동 종료되므로 보통 불필요)
set -uo pipefail

pkill -f "GWPOC_CAFFEINATE" 2>/dev/null || true
sleep 1
VBOXMANAGE="$(command -v VBoxManage)"
[ -z "$VBOXMANAGE" ] && { echo "VBoxManage not found"; exit 1; }

nohup bash -c "
# GWPOC_CAFFEINATE manager
while \"$VBOXMANAGE\" list runningvms 2>/dev/null | grep -q '1.36.1-gateway-poc'; do
  caffeinate -is -t 270
done
" > /tmp/gwpoc-caffeinate.log 2>&1 &
echo "caffeinate 매니저 시작 PID=$! (gateway-poc VM이 모두 halt되면 자동 종료)"
