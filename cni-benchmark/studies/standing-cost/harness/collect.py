#!/usr/bin/env python3
"""CNI 상시 자원 수집기.

추가 컴포넌트를 클러스터에 설치하지 않는다(측정 잡음 방지). 대신:
- CPU/메모리(working set, RSS): kubelet cadvisor 메트릭을 API 서버 프록시로 폴링
  (`/api/v1/nodes/<node>/proxy/metrics/cadvisor`). kubectl 인증을 재사용.
- eBPF map 커널 메모리: 노드에 ssh(NAT)로 들어가 bpftool map 목록의 bytes 합산.
  cilium/calico eBPF 조건에서만 값이 있음.

출력: JSONL 시계열 (1행 = 1샘플 시점의 대상 컨테이너/집계 스냅샷).

대상 컨테이너 = CNI와 서비스 플레인 관련 네임스페이스의 전부:
kube-system(kube-proxy, cilium, calico, antrea, kube-router, flannel 등),
calico-system, tigera-operator, kube-flannel. 파드명/컨테이너명 그대로 기록하고
분류는 분석 단계에서 한다 (수집은 낮은 가정, 분석에서 해석).
"""

import argparse
import json
import re
import subprocess
import sys
import time

CTX = "cni-benchmark"
TARGET_NS = ["kube-system", "calico-system", "tigera-operator", "kube-flannel"]
NODES = ["cp-k8s", "w1-k8s", "w2-k8s"]
NAT_PORTS = {"cp-k8s": 60350, "w1-k8s": 60351, "w2-k8s": 60352}

METRICS = {
    "container_cpu_usage_seconds_total": "cpu_seconds",
    "container_memory_working_set_bytes": "working_set",
    "container_memory_rss": "rss",
}

LABEL_RE = re.compile(r'(\w+)="([^"]*)"')


def run(cmd, timeout=30):
    # 타임아웃/일시 오류로 수집기 전체가 죽으면 안 된다 (본 캠페인 X2 rep1에서
    # kubectl 1회 지연으로 TimeoutExpired 미포착 -> 수집기 사망, 2026-08-03 수정).
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(cmd, returncode=124, stdout="", stderr="timeout")


def scrape_node(node):
    """cadvisor 메트릭에서 대상 ns 컨테이너의 지표 추출."""
    r = run(["kubectl", "--context", CTX, "get", "--raw",
             f"/api/v1/nodes/{node}/proxy/metrics/cadvisor"], timeout=25)
    if r.returncode != 0:
        return None
    out = {}
    for line in r.stdout.splitlines():
        if line.startswith("#"):
            continue
        name = line.split("{", 1)[0]
        if name not in METRICS:
            continue
        try:
            labels_str, value = line.split("{", 1)[1].rsplit("}", 1)
        except ValueError:
            continue
        labels = dict(LABEL_RE.findall(labels_str))
        ns = labels.get("namespace", "")
        container = labels.get("container", "")
        pod = labels.get("pod", "")
        if ns not in TARGET_NS or not container or container == "POD" or not pod:
            continue
        key = (ns, pod, container)
        out.setdefault(key, {})[METRICS[name]] = float(value.strip().split()[0])
    return out


VM_NAMES = {"cp-k8s": "cp-k8s-1.36.2", "w1-k8s": "w1-k8s-1.36.2", "w2-k8s": "w2-k8s-1.36.2"}


def scrape_bpf(node, ssh_key, cluster_dir):
    """bpftool map 메모리 합계 (bytes). 실패 시 None. VM별 키 사용."""
    port = NAT_PORTS[node]
    ssh_key = f"{cluster_dir}/.vagrant/machines/{VM_NAMES[node]}/virtualbox/private_key"
    cmd = ["ssh", "-n", "-i", ssh_key, "-p", str(port),
           "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
           "-o", "ConnectTimeout=8", "vagrant@127.0.0.1",
           "sudo bpftool map show -j 2>/dev/null || echo []"]
    try:
        r = run(cmd, timeout=20)
        maps = json.loads(r.stdout.strip() or "[]")
        total = 0
        count = 0
        for m in maps:
            b = m.get("bytes_memlock")
            if b:
                total += int(b)
                count += 1
        return {"bpf_memlock_bytes": total, "bpf_map_count": count}
    except Exception:
        return None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--out", required=True, help="JSONL 출력 파일")
    p.add_argument("--interval", type=int, default=15, help="샘플 간격 초")
    p.add_argument("--duration", type=int, default=0, help="0=무한 (러너가 종료시킴)")
    p.add_argument("--phase", default="", help="현재 페이즈 라벨 (러너가 파일로 갱신)")
    p.add_argument("--phase-file", default="", help="페이즈 라벨을 읽을 파일 (있으면 우선)")
    p.add_argument("--cluster-dir", default="", help="test-cluster 경로 (bpf ssh 키)")
    args = p.parse_args()

    ssh_key = ""
    if args.cluster_dir:
        ssh_key = f"{args.cluster_dir}/.vagrant/machines/cp-k8s-1.36.2/virtualbox/private_key"

    start = time.time()
    bpf_tick = 0
    with open(args.out, "a") as f:
        while True:
            now = time.time()
            if args.duration and now - start > args.duration:
                break
            phase = args.phase
            if args.phase_file:
                try:
                    phase = open(args.phase_file).read().strip()
                except OSError:
                    pass

            sample = {"ts": round(now, 1), "phase": phase, "nodes": {}}
            for node in NODES:
                metrics = scrape_node(node)
                entry = {"containers": []}
                if metrics is None:
                    entry["error"] = "scrape_failed"
                else:
                    for (ns, pod, container), vals in sorted(metrics.items()):
                        entry["containers"].append({
                            "ns": ns, "pod": pod, "container": container, **vals})
                # bpf는 4번에 1번 (부하 최소화)
                if ssh_key and bpf_tick % 4 == 0:
                    bpf = scrape_bpf(node, ssh_key, args.cluster_dir)
                    if bpf:
                        entry["bpf"] = bpf
                sample["nodes"][node] = entry

            f.write(json.dumps(sample, ensure_ascii=False) + "\n")
            f.flush()
            bpf_tick += 1

            elapsed = time.time() - now
            time.sleep(max(1, args.interval - elapsed))


if __name__ == "__main__":
    main()
