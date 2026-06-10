# test-cluster

Self-contained Kubernetes test environment for the Gateway API PoC. Provisions a 4-node (1 control-plane + 3 worker) cluster on VirtualBox via Vagrant, with Cilium as the CNI in kube-proxy replacement mode.

## Provenance

Provisioning logic adapted from the AIOps-Agent-Benchmark `test-cluster/`, which in turn derives from [sysnet4admin/_Lecture_k8s_learning.kit](https://github.com/sysnet4admin/_Lecture_k8s_learning.kit). Differences from the AIOps cluster: CNI is Cilium (not Calico), kube-proxy is replaced by Cilium eBPF, MetalLB serves the gateway IP pool `192.168.1.11-17`, and storage/metrics add-ons are dropped.

## Specs

| Component | Value |
|---|---|
| Kubernetes | v1.36.1 |
| Containerd | 2.2.3 (Ubuntu 24.04 Noble) |
| CNI | Cilium v1.19.4 (eBPF, kube-proxy replacement) |
| Load balancer | MetalLB v0.15.3 (L2 mode, pool `192.168.1.11-17`) |
| Architecture | arm64 (Apple Silicon, box `sysnet4admin/Ubuntu-k8s` 1.0.0) |
| Gateway implementations | installed separately (see below) |

| Node | vCPU | RAM | Private IP |
|---|---|---|---|
| cp-k8s | 2 | 4 GB | 192.168.1.150 |
| w1-k8s | 2 | 4 GB | 192.168.1.151 |
| w2-k8s | 2 | 4 GB | 192.168.1.152 |
| w3-k8s | 2 | 4 GB | 192.168.1.153 |

Total host footprint: 8 vCPU, 16 GB RAM.

## Scope: base cluster only

This directory provisions the **base cluster** (Kubernetes + Cilium + MetalLB). It does **not** install the 7 Gateway API implementations (NGINX, Envoy, Istio, Cilium, Kong, Traefik, kgateway; see SCORING.md ch.10). That is a separate implementation-install step so the base cluster stays a clean, snapshottable canvas. The measurement expects each implementation already installed with a LoadBalancer IP from the pool above.

## Prerequisites

- macOS (Apple Silicon / arm64) host with **VirtualBox** + **Vagrant**
- `sysnet4admin/Ubuntu-k8s` box v1.0.0 (arm64; auto-fetched on first `vagrant up`)
- Available host ports 60160-60163 (SSH forwarding)

## Lifecycle

```bash
./up.sh                    # provision + wait for MetalLB ready (~20-25 min first time)
./snapshot.sh              # save baseline snapshot (run once after up.sh completes)
./status.sh                # quick health check (nodes, pods, LB IPs)
./reset.sh                 # restore baseline snapshot (fast, ~30-60s)
./snapshot.sh my-checkpoint  # save named snapshot
./down.sh                  # destroy all VMs (with confirmation prompt)
```

## kubectl context

Context name: **`gateway-PoC`**

After `up.sh` completes the first time, import the kubeconfig (fetch `admin.conf`, rename cluster/user/context to `gateway-PoC`, merge into `~/.kube/config`).

## Notes

- kube-proxy is **not** installed: `kubeadm init` runs with `--skip-phases=addon/kube-proxy`, and Cilium is installed with `kubeProxyReplacement=true`, `k8sServiceHost=192.168.1.150`, `k8sServicePort=6443`.
- `extra_k8s_pkgs.sh` applies MetalLB, waits for its controller, then applies the `gateway-pool` IPAddressPool + L2Advertisement. `up.sh` polls for the `gateway-pool` resource as the readiness signal.
- The cluster uses a private VirtualBox network (`192.168.1.0/24`). Do not connect to any real Wi-Fi/LAN with an overlapping subnet or routing will break.
- Cilium's own Gateway API support is **not** enabled at base-cluster install (`gatewayAPI.enabled` is left off). Gateway API CRDs and per-implementation enablement (including `cilium-gw`) belong to the implementation-install step.
