#!/usr/bin/env python3
"""파일럿 데이터 품질 확인용 요약: metrics.jsonl -> 페이즈별 컨테이너 자원 표.

CPU는 counter라 인접 샘플 차분으로 rate(mCPU)를 계산. 메모리는 working set과
RSS의 페이즈별 평균/최대(MiB). bpf memlock은 노드별 평균(MiB).
"""

import json
import sys
from collections import defaultdict

from aggregate import pod_base_name


def mib(b):
    return round(b / 1048576, 1)


def main(path):
    rows = [json.loads(l) for l in open(path) if l.strip()]
    if not rows:
        print("빈 파일")
        return

    # (phase, ns/pod-prefix/container) -> 샘플 목록
    prev_cpu = {}
    agg = defaultdict(lambda: {"cpu_m": [], "ws": [], "rss": []})
    bpf = defaultdict(list)

    for row in rows:
        phase = row.get("phase", "?")
        for node, entry in row.get("nodes", {}).items():
            if "bpf" in entry:
                bpf[(phase, node)].append(entry["bpf"]["bpf_memlock_bytes"])
            for c in entry.get("containers", []):
                # 파드명에서 해시 접미사 제거해 그룹핑 (aggregate와 동일 규칙.
                # 구버전은 뒤 2토막 일괄 절단이라 kube-proxy -> "kube"로 과절단)
                pod_base = pod_base_name(c["pod"])
                key = (phase, c["ns"], pod_base, c["container"])
                ckey = (node, c["pod"], c["container"])
                if "cpu_seconds" in c:
                    if ckey in prev_cpu:
                        pt, pv = prev_cpu[ckey]
                        dt = row["ts"] - pt
                        if 0 < dt < 120:
                            rate_m = (c["cpu_seconds"] - pv) / dt * 1000
                            if rate_m >= 0:
                                agg[key]["cpu_m"].append(rate_m)
                    prev_cpu[ckey] = (row["ts"], c["cpu_seconds"])
                if "working_set" in c:
                    agg[key]["ws"].append(c["working_set"])
                if "rss" in c:
                    agg[key]["rss"].append(c["rss"])

    phases = []
    for row in rows:
        p = row.get("phase", "?")
        if not phases or phases[-1] != p:
            phases.append(p)
    print(f"샘플 {len(rows)}개, 페이즈 흐름: {' -> '.join(phases)}\n")

    print(f"{'phase':10} {'ns':14} {'pod':28} {'container':20} "
          f"{'cpu_mC avg/max':>14} {'ws MiB avg/max':>15} {'rss MiB avg':>12}")
    for key in sorted(agg):
        phase, ns, pod, container = key
        v = agg[key]
        if not v["ws"]:
            continue
        cpu_avg = sum(v["cpu_m"]) / len(v["cpu_m"]) if v["cpu_m"] else 0
        cpu_max = max(v["cpu_m"]) if v["cpu_m"] else 0
        ws_avg = mib(sum(v["ws"]) / len(v["ws"]))
        ws_max = mib(max(v["ws"]))
        rss_avg = mib(sum(v["rss"]) / len(v["rss"])) if v["rss"] else 0
        print(f"{phase:10} {ns:14} {pod:28} {container:20} "
              f"{cpu_avg:6.1f}/{cpu_max:6.1f} {ws_avg:7.1f}/{ws_max:7.1f} {rss_avg:12.1f}")

    if bpf:
        print("\nBPF memlock (노드별 평균 MiB):")
        for (phase, node), vals in sorted(bpf.items()):
            print(f"  {phase:10} {node:8} {mib(sum(vals)/len(vals)):8.1f}")


if __name__ == "__main__":
    main(sys.argv[1])
