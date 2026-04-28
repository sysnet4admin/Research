#!/usr/bin/env bash
# Save a snapshot across all VMs.
# Usage: ./snapshot.sh [name]   (default: baseline)

set -euo pipefail
source "$(dirname "$0")/config.sh"

NAME="${1:-$BASELINE_SNAPSHOT}"

cd "$CLUSTER_DIR"
echo "==> saving snapshot '$NAME' across all VMs"
vagrant snapshot save "$NAME"
vagrant snapshot list
