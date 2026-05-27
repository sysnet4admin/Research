#!/usr/bin/env bash
# Save a snapshot across all VMs.
# VM을 먼저 halt한 뒤 스냅샷을 찍고 재시작합니다.
# 실행 중 스냅샷은 VMDK CoW delta 손상 위험이 있습니다.
#
# Usage: ./snapshot.sh [name]   (default: baseline)

set -euo pipefail
source "$(dirname "$0")/config.sh"

NAME="${1:-$BASELINE_SNAPSHOT}"

cd "$CLUSTER_DIR"

echo "==> halting all VMs before snapshot (prevents VMDK corruption)"
vagrant halt

echo "==> saving snapshot '$NAME' across all VMs"
vagrant snapshot save "$NAME"
vagrant snapshot list

echo "==> restarting VMs"
vagrant up

echo "==> snapshot '$NAME' complete"
