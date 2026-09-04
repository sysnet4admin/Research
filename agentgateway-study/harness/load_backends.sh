#!/usr/bin/env bash
# aaif-benchmark 클러스터용 백엔드 이미지 적재.
# mcp-migration studies/stateless-scaleout/images/build_and_load.sh의 사본을
# 이 클러스터(포트 60261/60262, VM w{1,2}-k8s-1.37.0)로 맞춘 것. 원본은
# 발행 측정 자산이라 수정하지 않는다(REMEASURE.md 체크리스트).
# 사용: ./load_backends.sh [MCP_VER]   (기본 2.0.0 안정 버전)
set -euo pipefail

MCP_VER="${1:-2.0.0}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
REPO="$(cd "$STUDY/.." && pwd)"
IMAGES="$REPO/mcp-migration/studies/stateless-scaleout/images"
CLUSTER="$STUDY/test-cluster"

if ! docker info >/dev/null 2>&1; then
  echo "==> Docker 데몬이 없다. colima를 켠다"
  colima start || true
  sleep 5
  docker info >/dev/null 2>&1 || { echo "[중단] Docker 데몬에 붙지 못했다." >&2; exit 1; }
fi

A_IMG="mcp-pilot/a-server:2026.7.4"
B_IMG="mcp-pilot/b-server:${MCP_VER}"

echo "==> build $A_IMG"
docker build -q -f "$IMAGES/Dockerfile.a" -t "$A_IMG" "$IMAGES"
echo "==> build $B_IMG (MCP_VER=$MCP_VER)"
docker build -q -f "$IMAGES/Dockerfile.b" --build-arg MCP_VER="$MCP_VER" -t "$B_IMG" "$IMAGES"

load_to() { # load_to <ssh_port> <vm_name>
  local port="$1" vm="$2"
  local key="$CLUSTER/.vagrant/machines/$vm/virtualbox/private_key"
  echo "==> load into $vm (port $port)"
  for img in "$A_IMG" "$B_IMG"; do
    docker save "$img" | ssh -i "$key" -p "$port" \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      vagrant@127.0.0.1 "sudo ctr -n k8s.io images import -" | tail -1
  done
}

load_to 60261 w1-k8s-1.37.0
load_to 60262 w2-k8s-1.37.0

echo "==> 적재 확인"
for i in 1 2; do
  vm="w${i}-k8s-1.37.0"
  ssh -i "$CLUSTER/.vagrant/machines/$vm/virtualbox/private_key" -p "6026${i}" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    vagrant@127.0.0.1 "sudo ctr -n k8s.io images ls -q | grep mcp-pilot" | sed "s/^/  $vm: /"
done
