#!/usr/bin/env bash
# eBPF 맵 메모리가 어느 memory cgroup 에 매겨지는가 (2026-10-06, README "eBPF maps do not show up in kubectl top" 확인용).
# 측정 아님, 판정용 1회 관찰. 조건을 설치한 클러스터에서 워커 노드 1대를 본다.
#
# 기록하는 것(노드 w1):
#   1. uname -r (5.11 이후면 맵 메모리가 맵을 만든 프로세스의 memcg 에 매겨진다)
#   2. bpftool map show -j: 맵 수, bytes_memlock 합계, 맵을 가진 프로세스(pids) 별 합계
#   3. CNI 에이전트 컨테이너와 대조 컨테이너(kube-proxy)의 memory.current, memory.stat 전체
#      working set = memory.current - inactive_file (kubelet 과 같은 계산)
#   4. 노드 루트 cgroup 의 memory.stat 커널 항목
# 판정: 에이전트 cgroup 의 커널 메모리(kernel 또는 slab+vmalloc+percpu)가 맵 합계를 담을 만큼이면 working set 에 잡힌다.
#
# 사용: bpf_memcg_probe.sh <agent-comm 정규식> <OUT 파일>   예: bpf_memcg_probe.sh 'cilium-agent' runs/bpfmemcg-1006/ci1.txt
set -uo pipefail
AGENT="$1"; OUT="$2"; mkdir -p "$(dirname "$OUT")"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_DIR="$DIR/../../../test-cluster"
w1() { ssh -n -i "$CLUSTER_DIR/.vagrant/machines/w1-k8s-1.36.2/virtualbox/private_key" -p 60351 \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10 vagrant@127.0.0.1 "$@"; }
{
echo "# bpf memcg probe $(date '+%F %T') agent=$AGENT"
echo "## kernel"; w1 uname -r
echo "## bpftool maps"
w1 "sudo bpftool map show -j 2>/dev/null" | python3 -c '
import json,sys,collections
m=json.load(sys.stdin); tot=sum(int(x.get("bytes_memlock",0)) for x in m)
by=collections.Counter()
for x in m:
    owners=",".join(sorted({p.get("comm","?") for p in x.get("pids",[])})) or "(no pid: pinned or kernel)"
    by[owners]+=int(x.get("bytes_memlock",0))
print(f"maps={len(m)} bytes_memlock_total={tot} ({tot/1048576:.1f} MiB)")
for k,v in by.most_common(): print(f"  owner={k} bytes={v} ({v/1048576:.1f} MiB)")'
cg_of() { w1 "p=\$(pgrep -o -f '$1'); [ -n \"\$p\" ] && echo \$p && sed -n 's/^0:://p' /proc/\$p/cgroup"; }
dump() { # dump <label> <comm regex>
  local r; r=$(cg_of "$2"); local pid=$(echo "$r" | sed -n 1p) cg=$(echo "$r" | sed -n 2p)
  echo "## $1 pid=$pid cgroup=$cg"
  [ -z "$cg" ] && { echo "(프로세스 없음)"; return; }
  w1 "cd /sys/fs/cgroup$cg && c=\$(cat memory.current) && i=\$(awk '/^inactive_file /{print \$2}' memory.stat) && echo memory.current=\$c working_set=\$((c-i)) && grep -E '^(anon|file|kernel|kernel_stack|pagetables|percpu|sock|vmalloc|slab|slab_reclaimable|slab_unreclaimable|inactive_file) ' memory.stat"
}
dump "agent" "$AGENT"
dump "control(kube-proxy)" "kube-proxy"
echo "## node root memory.stat (kernel 항목)"
w1 "grep -E '^(kernel|percpu|vmalloc|slab) ' /sys/fs/cgroup/memory.stat 2>/dev/null || echo '(root memory.stat 없음)'"
} > "$OUT" 2>&1
cat "$OUT"
