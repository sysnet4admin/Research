# How much CPU and memory does a CNI actually use?

[한국어](README_ko.md)

A CNI (Container Network Interface, the component that wires pods into the
network) is something you pick once when you build a cluster and rarely look at
again. As a result, it is hard to find any organized data on how much CPU and
memory CNI agents and controllers consume day to day. Throughput benchmarks are
everywhere, but we could not find a public source that compares standing cost
under identical conditions, and vendor docs do not state it either: Cilium
ships its helm chart without resource requests, and a Calico maintainer
declined a request to publish recommended values. Search results for these
numbers are often filled by sources with no traceable origin.

This repository is the result of measuring that standing cost with one
procedure and one toolset. We split Calico Open Source, Cilium, Flannel,
Antrea, and kube-router into 14 conditions and collected CPU, memory, and eBPF
map kernel memory (the kernel-side storage that eBPF programs use for state)
across 6 phases, from a quiet idle to pod churn (pods being deleted and
recreated repeatedly, as happens during frequent deployments or failure
recovery). Each condition ran the full phase sequence 5 to 6 times, giving 73
valid measurement runs over 9 days with no human intervention.

CPU values are in millicores (mC): 1,000mC is one core, the same unit as a
`100m` CPU request in Kubernetes. Memory is working set (the in-use memory the
OS will not reclaim, the value `kubectl top` reports).

## Summary

- What separates the conditions is memory usage, not CPU. Idle CPU stayed
  under 0.13 cores (cluster total) in every condition, but memory usage spans
  an 8x range between the lightest and heaviest configurations.
- eBPF-based CNIs consume additional eBPF map kernel memory that process
  metrics do not capture. Comparisons based on `kubectl top`-style tools alone
  leave this share out.
- Just switching kube-proxy from iptables mode to nftables mode cut
  kube-proxy memory usage by 70%. Official material covers the latency
  improvement of nftables mode; the resident-memory saving had not been
  published as a number.
- kube-router in all-features mode (pod networking, NetworkPolicy, and the
  service proxy all handled by one kube-router daemon) was the lightest of all
  conditions at idle. But after going through pod churn, its CPU stayed at
  about one core per node even though the number of Services and pods was
  unchanged.
- Turning on observability features such as Hubble or FlowExporter added very
  little: +5 to 22MiB of agent memory.

## Which one should you pick?

Plotting the 14 conditions on two axes gives the picture below. The x-axis is
idle memory, what the stack occupies all the time; the y-axis is churn-phase
CPU, what it additionally burns while pods keep getting replaced (1,000mC =
1 core). The further toward the lower left, the less a configuration consumes
both at rest and under load.

![Standing-cost map: idle memory vs churn CPU](studies/standing-cost/assets/standing-cost-map.svg)

Organized by situation, the results read as follows. Standing cost is only one
of several criteria for choosing a CNI; features, performance, and operational
experience belong in the decision too. The recommendations below are grounded
only in what this measurement covered.

| Situation | Suggested configuration | Basis (this measurement) |
|---|---|---|
| Small nodes, no need for NetworkPolicy | Flannel + kube-proxy nftables (Fl1n) | Lowest memory of all conditions (209MiB), and the smallest extra CPU during pod replacement (churn 147mC) |
| NetworkPolicy required, memory tight | Calico manifest install (Ca3) | Lowest memory among policy-capable conditions (472MiB) |
| Calico managed via operator | Calico operator (Ca1) | Same features as Ca3 with 533MiB more memory; that is the price of the management convenience |
| Heading toward eBPF dataplane, observability, kube-proxy replacement | Cilium (Ci1~Ci4) | Budget about 530~800MiB per node (maps included); CPU stays flat even during pod replacement (churn 131mC in the KPR configuration) |
| OVS required, or already in the Antrea ecosystem | Antrea (An1) | Mid-range on both memory (758MiB) and pod-replacement CPU (churn 285mC) |
| BGP routing without an overlay, minimal footprint | kube-router CNI only + kube-proxy (Ku2) | Light at 369MiB idle. All-features mode (Ku1) is hard to recommend for clusters with frequent pod replacement, because of the churn behavior in finding 3 below |

Whichever configuration you pick, if it uses kube-proxy, the nftables mode
switch is worth evaluating alongside it. It was the largest saving in this
measurement that did not involve changing the CNI.

## Conditions

| Code | Configuration | Variable isolated |
|---|---|---|
| Ca1 | Calico operator install, iptables, BGP off | Calico baseline |
| Ca2 | Ca1 + eBPF dataplane | dataplane |
| Ca3 | Calico manifest install (vxlan) | install method |
| Ca4 | Ca1 + BGP on | routing protocol |
| Ci1 | Cilium helm defaults (veth, VXLAN, Hubble on) | Cilium baseline |
| Ci2 | Ci1 + Hubble off | observability |
| Ci3 | Ci2 + kube-proxy replacement (KPR; Cilium takes over kube-proxy) | service plane |
| Ci4 | Ci3 + netkit (the kernel 6.7 pod-link device replacing veth) | datapath device |
| Fl1 | Flannel + kube-proxy iptables | minimal baseline |
| Fl1n | Fl1 + kube-proxy nftables | kube-proxy mode |
| An1 | Antrea defaults (OVS, Open vSwitch based) | Antrea baseline |
| An2 | An1 + FlowExporter on | observability |
| Ku1 | kube-router all-features: pod networking + NetworkPolicy + IPVS (IP Virtual Server, the kernel L4 load balancer) service proxy, kube-proxy removed | integrated |
| Ku2 | kube-router pod networking only, Services stay on kube-proxy | split |

Versions are pinned: Calico 3.32, Cilium 1.19, Flannel 0.28.7, Antrea 2.6.2,
kube-router 2.10.0, Kubernetes 1.36.2. kube-proxy runs in iptables mode in
every condition except Fl1n. nftables mode went GA in 1.33, but iptables is
still the default in 1.36, so the default that most clusters actually run is
what we used as the baseline.

Phases run in order: idle (1~2h), pod density ramp (0 to 60), 100
NetworkPolicies, 200 Services, churn (delete 10 pods every 20 seconds), node
drain and rejoin. Every condition switch restores a CNI-less base snapshot so
nothing from the previous condition survives.

## Environment

- 3 nodes (1 control plane, 2 workers), 2 CPUs and 4GB each, Ubuntu 24.04
  arm64, kernel 6.8, VirtualBox, hosted on a single Apple Silicon laptop.
- Because this is a virtualized environment, we did not measure throughput or
  latency: the virtual switch would blend into the numbers and they could not
  be attributed to the CNI itself. Traffic and object load are used only as
  stimuli that trigger resource consumption.
- Collection uses kubelet cadvisor metrics (via the API-server proxy, 15s
  interval) and per-node bpftool (eBPF map memlock). We installed no
  collection components into the cluster under test, since those would
  themselves become measurement noise.

## Results: networking stack totals

Each cell is "CPU / memory": what the whole networking stack (every CNI
component, plus kube-proxy where present) used during that phase as a
3-node-cluster total, CPU in mC and working set in MiB, median across repeats.
For example, Ca1's idle cell 84 / 1005 means 84mC (0.08 cores) of CPU and
1,005MiB of memory at rest. Conditions that replace kube-proxy (Ca2, Ci3, Ci4,
Ku1) are summed exactly as deployed, which is what makes the totals comparable
across conditions.

Columns are measurement phases: idle is quiet time, service is with 200
Services in place, churn is continuous pod replacement, node is draining and
rejoining one node. Of the 6 phases, density (60 pods) and policy (100
NetworkPolicies) differed little from idle and are omitted here; full-phase
values are in the detailed tables linked below. The last column is eBPF map
memory at idle, node total, in MiB.

| Condition | idle | service | churn | node | eBPF maps |
|---|---|---|---|---|---|
| Calico operator (Ca1) | 84 / 1005 | 93 / 1163 | 418 / 1319 | 110 / 1233 | 3 |
| Calico eBPF (Ca2) | 87 / 920 | 88 / 1029 | 185 / 1096 | 87 / 1044 | 521 |
| Calico manifest (Ca3) | 80 / 472 | 92 / 614 | 468 / 748 | 118 / 714 | 3 |
| Calico +BGP (Ca4) | 84 / 1077 | 95 / 1249 | 445 / 1458 | 112 / 1340 | 3 |
| Cilium default (Ci1) | 110 / 1574 | 115 / 1795 | 279 / 2003 | 119 / 1943 | 412 |
| Cilium Hubble off (Ci2) | 116 / 1551 | 115 / 1763 | 280 / 1963 | 120 / 1907 | 412 |
| Cilium +KPR (Ci3) | 123 / 1705 | 127 / 1826 | 131 / 1926 | 126 / 1894 | 712 |
| Cilium +netkit (Ci4) | 127 / 1705 | 129 / 1823 | 133 / 1927 | 128 / 1892 | 712 |
| Flannel default (Fl1) | 24 / 319 | 23 / 410 | 193 / 509 | 28 / 492 | 0 |
| Flannel nftables (Fl1n) | 23 / 209 | 21 / 248 | 147 / 323 | 24 / 277 | 0 |
| Antrea default (An1) | 60 / 758 | 61 / 954 | 285 / 1101 | 66 / 1108 | 0 |
| Antrea FlowExporter (An2) | 50 / 762 | 53 / 955 | 284 / 1108 | 60 / 1115 | 0 |
| kube-router all-features (Ku1) | 2 / 215 | 77 / 315 | 3355 / 1159 | 3158 / 1503 | 0 |
| kube-router CNI only (Ku2) | 3 / 369 | 6 / 538 | 406 / 676 | 25 / 626 | 0 |

Per-component tables (agents, controllers, operators split out, RSS included)
are in [studies/standing-cost/analysis/summary.md](studies/standing-cost/analysis/summary.md).

## Before you read the numbers

These are not CNI comparison results; they are things you need to know to
interpret the table above, or to compare these numbers with other sources.
They apply equally if you run a measurement like this yourself.

### eBPF maps do not show up in kubectl top

The map kernel memory that eBPF-based CNIs use lives outside process metrics.
Measured node totals: Cilium default 412MiB, Cilium KPR 712MiB, Calico eBPF
521MiB. Calico eBPF actually has a smaller process working set than the
iptables configuration (920 vs 1005MiB), so leaving maps out can flip the
comparison. Memory comparisons of eBPF CNIs need bpftool accounting included.

### working set and RSS differ by up to 5x per component

Memory values in this document are working set. Working set includes not only
RSS (Resident Set Size, the process's own memory resident in RAM) but also
kernel memory and page cache charged to the cgroup. Which metric you read can
change the same container's number substantially: cilium-agent at idle shows
1,137MiB working set vs 236MiB RSS (4.8x), kube-proxy 157.5 vs 33.4MiB (4.7x).
When comparing against other sources, check which metric they use first; the
detailed tables in this repository carry RSS alongside.

### absolute CPU numbers shift between measurement windows

The same condition showed 20~33% different absolute CPU depending on host
conditions at measurement time (verified using Kubernetes's own components as
a control group). Only comparisons within the same measurement window are
valid, and the CPU column above should be read for ranking and rough scale.
The 14 conditions here rotated within each repetition round, so
condition-to-condition comparisons are not affected by this drift.

## Findings

### 1. Memory usage is what separates the conditions

Idle CPU topped out at 127mC (0.13 cores, cluster total) even in the heaviest
condition, so day-to-day CPU is unlikely to be a problem whichever CNI you
pick. Memory is different: while Flannel with nftables uses 209MiB, Cilium's
kube-proxy-replacement configuration uses 1,705MiB, and adding eBPF maps
widens the gap further. On 4GB nodes, whether the networking stack occupies
100MiB or 800MiB changes how much memory is left for workloads.

### 2. Switching kube-proxy to nftables mode alone cut memory usage by 70%

Some background first: nftables mode is the successor Kubernetes built to fix
the performance problems of iptables mode, whose rule count grows with the
number of Services and endpoints and whose packet latency grows with it. The
nftables mode uses verdict maps to make lookup cost independent of Service
count. The official blog post
[NFTables mode for kube-proxy](https://kubernetes.io/blog/2025/02/28/nftables-kube-proxy/)
shows the latency improvement in numbers. What that material does not cover is
the CPU and memory of the kube-proxy process itself.

This measurement fills that in. Comparing Fl1 and Fl1n, identical Flannel with
only the kube-proxy mode changed, phase by phase:

![kube-proxy memory usage: iptables vs nftables](studies/standing-cost/assets/kube-proxy-nftables.svg)

kube-proxy's working set dropped from 157.5MiB to 46.8MiB at idle (-70%), and
the direction held with 200 Services in place (-65%), during churn (-54%), and
through node drain (-65%). CPU was lower too: 133mC vs 179mC during churn. So
nftables mode delivers a resident-memory saving on top of the latency
improvement the official material describes. It is still not the default in
1.36 for compatibility reasons, so you have to turn it on, and it was the
largest saving in this measurement that did not involve changing the CNI.

### 3. kube-router all-features mode does not come back down after churn

kube-router can toggle pod networking, NetworkPolicy, and its service proxy
independently. Ku1 enables all three, using the upstream all-features manifest
as-is with kube-proxy removed. Ku1 is the lightest of all conditions at idle
(2mC / 215MiB). But once churn starts, it climbs to 3,355mC cluster total
(about 1.1 cores per node) and stays at 3,158mC through the following phase.
All 5 repetitions produced the same numbers.

We reproduced it once separately to narrow the cause. There were no pod
restarts, no OOM kills, no error logs, no netlink storm, and no lingering IPVS
drain entries; the CPU was consumed by a userspace loop in the kube-router
process. The most telling observation is history dependence: before churn, the
same object scale (200 Services, 12,008 endpoints) cost 77mC, but after one
churn episode the same scale holds at 3,300mC, and deleting the load objects
returns it to idle within 90 seconds. Our reading is that churn pushes the
sync loop into continuous re-execution, and since one sync pass costs in
proportion to Services times endpoints, CPU cannot come down while that scale
persists. Ku2, which leaves the service proxy to kube-proxy, was normal under
the same load (churn 406mC, then 25mC), so the cause most likely lies in
kube-router's IPVS service proxy; we did not identify which internal operation
is responsible. Pinning that down would need profiling enabled, and is a
follow-up investigation if needed.

### 4. For Calico, the install method changes memory usage more than the dataplane does

On the same iptables dataplane, the operator install (Ca1) uses 533MiB more
idle memory than the manifest install (Ca3), because two Typha replicas, two
calico-apiservers, csi-node-driver, tigera-operator, and kube-controllers all
stay resident. By contrast, switching the dataplane to eBPF (Ca2 vs Ca1)
changes process memory by only 85MiB. How you install weighs more on resident
memory usage than which dataplane you run. Turning BGP on (Ca4) added 72MiB
over Ca1.

### 5. Using observability features adds very little

Comparing Ci1 (Hubble on, the helm default, no relay or ui) against Ci2
(Hubble off): about 22MiB of agent working set, with CPU inside
repetition-to-repetition variance. Antrea's FlowExporter (no collector
deployed) trended the same: +5~10MiB agent memory, no CPU increase. The real
cost of an observability stack appears to come from the extra components
(relay, ui, collectors), not from the feature toggle itself. Those extra
components are outside this measurement's scope.

### 6. netkit changes nothing in standing cost

Pods connect to the host through a virtual device. Using netkit, the kernel
6.7 device built to replace the veth standard, lets packets skip the host-side
detour; Cilium supports it from 1.16 as a performance improvement. Comparing
Ci3 (veth) and Ci4 (netkit), every phase is within noise. netkit changes the
path packets take, so we expected it not to show up on the standing-cost axis,
and it did not. From a standing-cost perspective there is no reason to hold
back on netkit.

## Limits

- This is a small 3-node measurement on virtualization. Do not extrapolate the
  absolute values to large clusters: anything that scales with Typha placement
  thresholds, identity counts, or endpoint counts will differ at scale.
- Throughput and latency are not measured. Performance comparisons belong to
  bare-metal benchmarks; this measurement only answers what the stack consumes
  day to day.
- Encryption (WireGuard, IPsec) was off. Observability extras (Hubble relay,
  flow-aggregator) are out of scope.

## Reproducing

```
test-cluster/     Vagrant 3-node cluster, CNI-less base snapshot
conditions/       14 install scripts (pinned versions, prefetched images)
harness/          measurement automation (runner, load, collector, aggregation, charts)
```

```bash
# 9-day unattended measurement (about 4.5h per condition per repetition)
./harness/launch_campaign.sh 9

# aggregation and charts
python3 harness/aggregate.py runs/<run dir> --json analysis/summary.json
python3 harness/chart.py analysis/summary.json en > assets/standing-cost-map.svg
```

The aggregation scripts and the aggregated tables are in this repository. The
raw data (73 JSONL time series, about 170MB) is kept outside git for size and
will be provided alongside the public release. Note that condition codes in
the data directories and scripts keep their original measurement-time names,
which differ from this document: C=Ca (Calico), X=Ci (Cilium), F=Fl (Flannel),
A=An (Antrea), K=Ku (kube-router).
