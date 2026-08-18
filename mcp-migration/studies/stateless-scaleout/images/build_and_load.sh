#!/usr/bin/env bash
# 이미지 빌드(호스트 docker, arm64) 후 워커 containerd(k8s.io ns)로 적재.
# 레지스트리 없이 NAT ssh(60251/60252)로 docker save 스트림을 ctr import에 연결.
# 사용: ./build_and_load.sh [MCP_VER]   (기본 2.0.0 안정 버전)
set -euo pipefail

MCP_VER="${1:-2.0.0}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER="$DIR/../../../test-cluster"

# Docker 데몬 확인. 이 머신은 Docker Desktop이 아니라 colima가 데몬을 준다.
# colima는 로그인이나 부팅으로 자동 기동하지 않으므로(LaunchAgent 없음) 사람이
# 켜지 않으면 꺼져 있다. 2026-08-10 무인 재현 검증이 정확히 여기서 멈췄는데,
# 그때는 확인이 없어서 빌드 실패를 안고 배포까지 진행돼 mcp-b가 못 떴다.
# 상시 기동은 하지 않는다. colima가 4 CPU와 8GB를 잡는데 같은 머신에서 측정용
# VM 3대가 돌기 때문이다. 필요할 때만 켠다.
if ! docker info >/dev/null 2>&1; then
  echo "==> Docker 데몬이 없다. colima를 켠다 (AUTO_START_COLIMA=0으로 끌 수 있다)"
  if [ "${AUTO_START_COLIMA:-1}" = "1" ] && command -v colima >/dev/null 2>&1; then
    colima start || true
    sleep 5
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "[중단] Docker 데몬에 붙지 못했다." >&2
    echo "       colima status 로 상태를 보고 colima start 로 켠 뒤 다시 실행한다." >&2
    exit 1
  fi
  echo "==> Docker 데몬 준비됨"
fi

A_IMG="mcp-pilot/a-server:2026.7.4"
B_IMG="mcp-pilot/b-server:${MCP_VER}"

echo "==> build $A_IMG"
docker build -q -f "$DIR/Dockerfile.a" -t "$A_IMG" "$DIR"
echo "==> build $B_IMG (MCP_VER=$MCP_VER)"
docker build -q -f "$DIR/Dockerfile.b" --build-arg MCP_VER="$MCP_VER" -t "$B_IMG" "$DIR"

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

load_to 60251 w1-k8s-1.36.2
load_to 60252 w2-k8s-1.36.2

echo "==> 적재 확인"
for port in 60251 60252; do
  vm="w$((port-60250))-k8s-1.36.2"
  ssh -i "$CLUSTER/.vagrant/machines/$vm/virtualbox/private_key" -p "$port" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    vagrant@127.0.0.1 "sudo ctr -n k8s.io images ls -q | grep mcp-pilot" | sed "s/^/  $vm: /"
done
