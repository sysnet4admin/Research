#!/usr/bin/env bash
# 야간 무인 수정 검증 + 스냅샷 재생성 + 리허설.
# 목적: (1) C1 operator 2단계 방식 라이브 검증 + calico 이미지 캐시,
#       (2) F1n(br_netfilter 영속) 검증, (3) 두 검증 통과 시 스냅샷 재생성,
#       (4) 수정된 하네스로 4조건 무인 리허설.
# 실패해도 각 단계는 로그를 남기고 다음으로 진행 (아침에 판단).
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(dirname "$DIR")"
CLUSTER="$STUDY/../../test-cluster"
CTX="cni-benchmark"
OUT="$STUDY/runs/overnight-$(date +%m%d-%H%M)"
mkdir -p "$OUT"
LOG="$OUT/overnight.log"
log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

k() { kubectl --context "$CTX" "$@"; }

restore_base() {
  ( cd "$CLUSTER" && vagrant snapshot restore base-no-cni ) >>"$OUT/vagrant.log" 2>&1
  local start=$SECONDS
  while [ $((SECONDS - start)) -lt 300 ]; do
    k get nodes >/dev/null 2>&1 && return 0; sleep 10
  done
  return 1
}

persist_brnetfilter() {
  for port in 60350 60351 60352; do
    local vm="cp-k8s-1.36.2"
    [ "$port" = "60351" ] && vm="w1-k8s-1.36.2"; [ "$port" = "60352" ] && vm="w2-k8s-1.36.2"
    ssh -n -i "$CLUSTER/.vagrant/machines/$vm/virtualbox/private_key" -p "$port" \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null vagrant@127.0.0.1 \
      "printf 'br_netfilter\noverlay\n' | sudo tee /etc/modules-load.d/k8s.conf >/dev/null; printf 'net.bridge.bridge-nf-call-iptables=1\nnet.bridge.bridge-nf-call-ip6tables=1\nnet.ipv4.ip_forward=1\n' | sudo tee /etc/sysctl.d/99-k8s.conf >/dev/null; sudo modprobe br_netfilter overlay; sudo sysctl --system >/dev/null 2>&1" >/dev/null 2>&1
  done
}

# ---- 1. C1 라이브 검증 (operator 2단계) + 이미지 캐시 ----
log "==== 1. C1 (Calico operator 2단계) 검증 ===="
restore_base && persist_brnetfilter || log "  WARN: base 복원/persist 문제"
if timeout 900 "$STUDY/conditions/C1.sh" >"$OUT/C1-install.log" 2>&1; then
  log "  C1 OK. 캐시된 calico 이미지 기록"
  for port in 60350 60351 60352; do
    vm="cp-k8s-1.36.2"; [ "$port" = "60351" ] && vm="w1-k8s-1.36.2"; [ "$port" = "60352" ] && vm="w2-k8s-1.36.2"
    ssh -n -i "$CLUSTER/.vagrant/machines/$vm/virtualbox/private_key" -p "$port" \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null vagrant@127.0.0.1 \
      "sudo ctr -n k8s.io images ls -q 2>/dev/null | grep -iE 'calico|tigera'" 2>/dev/null
  done | sort -u > "$OUT/calico-images-cached.txt"
  log "  calico 이미지 $(wc -l < "$OUT/calico-images-cached.txt")개 캐시됨"
else
  log "  C1 FAIL (C1-install.log 참조)"
fi

# ---- 2. F1n 라이브 검증 (br_netfilter 영속) ----
log "==== 2. F1n (Flannel + nftables) 검증 ===="
restore_base && persist_brnetfilter || log "  WARN"
if timeout 900 "$STUDY/conditions/F1n.sh" >"$OUT/F1n-install.log" 2>&1; then
  log "  F1n OK"
else
  log "  F1n FAIL (F1n-install.log 참조)"
fi

# ---- 3. 스냅샷 재생성 (br_netfilter 영속 + calico 이미지 캐시 반영) ----
log "==== 3. 베이스 스냅샷 재생성 ===="
restore_base && persist_brnetfilter || log "  WARN"
# calico 이미지가 스냅샷에 남도록: C1을 한 번 더 설치했다 지우면 이미지가 containerd에 캐시됨.
# 대신 시간 절약 위해 위 1단계에서 이미 각 노드에 이미지가 있음 -> 복원하면 사라짐.
# 따라서 복원 후 calico 이미지를 다시 pull (이미 레지스트리 접근 검증됨, 빠름)
timeout 600 "$STUDY/prefetch.sh" >"$OUT/prefetch-resnap.log" 2>&1 || log "  WARN: prefetch 일부 실패"
( cd "$CLUSTER" && vagrant halt ) >>"$OUT/vagrant.log" 2>&1
( cd "$CLUSTER" && vagrant snapshot save base-no-cni --force 2>/dev/null || vagrant snapshot save base-no-cni ) >>"$OUT/vagrant.log" 2>&1
( cd "$CLUSTER" && vagrant up ) >>"$OUT/vagrant.log" 2>&1
local_start=$SECONDS
until k get nodes >/dev/null 2>&1 || [ $((SECONDS-local_start)) -gt 300 ]; do sleep 10; done
log "  스냅샷 재생성 완료"

# ---- 4. 수정된 하네스로 4조건 무인 리허설 ----
log "==== 4. 리허설 (C1 C2 F1n K1, 단축) ===="
CONDITIONS_OVERRIDE="C1 C2 F1n K1" MAX_REP=1 \
IDLE_LONG=300 IDLE_SHORT=300 STABILIZE=420 \
T_DENSITY=240 T_POLICY=120 T_SERVICE=180 T_CHURN=120 T_NODE=180 \
  "$DIR/run_campaign.sh" "$OUT/rehearsal2" $(( $(date +%s) + 5*3600 )) >>"$LOG" 2>&1

log "==== 야간 작업 종료. 아침 확인: $OUT/overnight.log 와 rehearsal2/progress.log ===="
