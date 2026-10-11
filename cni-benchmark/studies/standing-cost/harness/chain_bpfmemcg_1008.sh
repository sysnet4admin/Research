#!/usr/bin/env bash
# eBPF 맵 메모리 후속 확인 체인 (2026-10-08). 10/6 판정(runs/bpfmemcg-1006)에서 남긴 두 가지를 본다.
#   1. Ci3(KPR), Ci4(netkit) 에서도 맵이 cilium-agent 컨테이너 working set 안인가 (bpf_memcg_probe.sh)
#   2. kubectl top(metrics-server) 이 보여 주는 값이 컨테이너 working set 인가 파드 단위인가 (Ci1, Ca2)
# 측정 아님, 판정용 1회 관찰.
#
# 시작 조건: 실행 중인 VM 이 하나도 없을 때(다른 측정과 겹치지 않게). START_BY 까지 시작하지 못하면 erofs 측정(runs/window-1007)이
# 끝난 뒤(progress.log 의 \"러너 종료\")에 돈다.
# 끝나면(실패해도) 기준 스냅샷으로 되돌리고 VM 을 끈다. 그래야 뒤에 기다리는 erofs 체인이 시작한다.
# 기동: caffeinate -i nohup harness/chain_bpfmemcg_1008.sh > /tmp/cni-bpfmemcg-1008.log 2>&1 & disown
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; STUDY="$(cd "$DIR/.." && pwd)"
CLUSTER="$STUDY/../../test-cluster"
OUT="$STUDY/runs/bpfmemcg-1008"; mkdir -p "$OUT"
START_BY="${START_BY:-2026-10-08 22:00}"
CTX="cni-benchmark"
k() { kubectl --context "$CTX" "$@"; }
say() { echo "[cni $(date '+%m-%d %H:%M:%S')] $*" | tee -a "$OUT/progress.log"; }

SB=$(date -j -f "%Y-%m-%d %H:%M" "$START_BY" +%s)
EROFS_LOG="${EROFS_LOG:-$STUDY/../../../erofs-benchmark/runs/window-1007/progress.log}"
novm() { [ "$(VBoxManage list runningvms 2>/dev/null | wc -l | tr -d ' ')" = 0 ]; }
erofs_done() { [ -f "$EROFS_LOG" ] && tail -5 "$EROFS_LOG" | grep -q "러너 종료"; }
erofs_started() { [ -f "$EROFS_LOG" ] && [ "$(stat -f %m "$EROFS_LOG")" -ge "$T0" ]; }
T0=$(date +%s)
say "대기: 실행 중인 VM 이 없어질 때까지 (시한 $START_BY. 넘기면 erofs 가 끝난 뒤에 돈다)"
# 2026-10-08 수정: 시한을 넘기면 끝내지 않고 erofs 측정이 끝나기를 기다렸다가 돈다(월요일까지 확인하는 사람이 없음).
NB=$(date -j -f "%Y-%m-%d %H:%M" "${NOT_BEFORE:-2000-01-01 00:00}" +%s)
say "시작 가능 시각: ${NOT_BEFORE:-제한 없음}"
while :; do
  # 2026-10-08 추가: NOT_BEFORE 전에는 시작하지 않는다(라이너 측정이 길어져 금요일 아침으로 옮김)
  if [ "$(date +%s)" -lt "$NB" ]; then sleep 60; continue; fi
  if [ "$(date +%s)" -lt "$SB" ]; then
    # 시한 전: erofs 가 아직 시작하지 않았고 VM 이 없으면 바로 시작
    novm && ! erofs_started && break
  else
    # 시한 뒤: erofs 가 끝났고(러너 종료) VM 이 없을 때
    erofs_done && erofs_started && novm && { say "erofs 가 끝났다. 이어서 시작"; break; }
  fi
  sleep 60
done
pmset -g batt | head -1 | grep -q "AC Power" || say "경고: AC 전원이 아니다"

finish() {
  say "정리: 기준 스냅샷 복원과 VM 정지"
  (cd "$CLUSTER" && bash reset.sh >/dev/null 2>&1; vagrant halt >/dev/null 2>&1)
  say "== 체인 종료"
  ( cd "$STUDY/../.." && cd .. && git add -f cni-benchmark/studies/standing-cost/runs/bpfmemcg-1008 >/dev/null 2>&1 \
    && git commit -qm "cni-benchmark: runs/bpfmemcg-1008 eBPF 맵 후속 확인 결과" >/dev/null 2>&1 \
    && env -u GITHUB_TOKEN git pull -q --rebase --autostash origin main >/dev/null 2>&1 \
    && env -u GITHUB_TOKEN git push -q origin main >/dev/null 2>&1 ) || true
}
trap finish EXIT

fresh() { # fresh <조건 스크립트>
  say "== $1: 기준 스냅샷 복원"
  (cd "$CLUSTER" && bash reset.sh >/dev/null 2>&1)
  for i in $(seq 1 40); do [ "$(k get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')" = 3 ] && break; sleep 10; done
  say "$1 설치"
  if ! timeout 1200 bash "$STUDY/conditions/$1.sh" >> "$OUT/install-$1.log" 2>&1; then say "$1 설치 실패(install-$1.log)"; return 1; fi
  say "$1 준비 완료. 안정화 2분"; sleep 120
}

top_check() { # top_check <라벨> <ns> <파드 레이블 셀렉터>
  local L="$1" NS="$2" SEL="$3" f="$OUT/top-$1.txt"
  say "$L: metrics-server 설치"
  python3 -c 'import sys;print(open(sys.argv[1]).read().replace("        - --metric-resolution=15s","        - --metric-resolution=15s\n        - --kubelet-insecure-tls"))' \
    "$STUDY/vendor/metrics-server-components.yaml" | k apply -f - >> "$OUT/install-ms-$L.log" 2>&1
  k -n kube-system rollout status deploy/metrics-server --timeout=300s >> "$OUT/install-ms-$L.log" 2>&1 || { say "$L: metrics-server 준비 실패"; return 1; }
  for i in $(seq 1 30); do k top pod -n "$NS" -l "$SEL" >/dev/null 2>&1 && break; sleep 10; done
  sleep 30
  {
    echo "# $L kubectl top 대 kubelet 지표 $(date '+%F %T')"
    echo "## kubectl top pod -n $NS -l $SEL"; k top pod -n "$NS" -l "$SEL" 2>&1
    echo "## kubectl top pod --containers"; k top pod -n "$NS" -l "$SEL" --containers 2>&1
    echo "## PodMetrics 원문(metrics.k8s.io)"; k get --raw "/apis/metrics.k8s.io/v1beta1/namespaces/$NS/pods" 2>&1 | python3 -c '
import json,sys
d=json.load(sys.stdin)
for p in d.get("items",[]):
    print(p["metadata"]["name"], [(c["name"], c["usage"]["memory"]) for c in p["containers"]])' 2>&1
    for n in w1-k8s; do
      echo "## kubelet /metrics/resource ($n) container 와 pod working set"
      k get --raw "/api/v1/nodes/$n/proxy/metrics/resource" 2>/dev/null | grep -E "^(container|pod)_memory_working_set_bytes" | grep "namespace=\"$NS\"" | grep -E "$(echo "$SEL" | sed 's/.*=//')"
    done
  } > "$f" 2>&1
  say "$L: 기록 $f"
}

# 1) Ci1 (Cilium 기본): 맵 위치 다시 보고 kubectl top 비교
fresh X1 && { bash "$DIR/bpf_memcg_probe.sh" 'cilium-agent' "$OUT/ci1.txt" >/dev/null 2>&1; top_check ci1 kube-system k8s-app=cilium; }
# 2) Ca2 (Calico eBPF): 파드 단위에 매겨지는 맵이 kubectl top 에 보이는가
fresh C2 && { bash "$DIR/bpf_memcg_probe.sh" 'calico-node -felix' "$OUT/ca2.txt" >/dev/null 2>&1; top_check ca2 calico-system k8s-app=calico-node; }
# 3) Ci3 (KPR), 4) Ci4 (netkit): 맵 위치만
fresh X3 && bash "$DIR/bpf_memcg_probe.sh" 'cilium-agent' "$OUT/ci3.txt" >/dev/null 2>&1
fresh X4 && bash "$DIR/bpf_memcg_probe.sh" 'cilium-agent' "$OUT/ci4.txt" >/dev/null 2>&1
say "모든 조건 끝"
