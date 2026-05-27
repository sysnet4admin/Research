# test-cluster

Self-contained Kubernetes test environment for the AIOps Agent Benchmark. Provisions a 4-node (1 control-plane + 3 worker) cluster on VirtualBox via Vagrant.

## Provenance

Provisioning logic originally adapted from [sysnet4admin/_Lecture_k8s_learning.kit/B/B.001/U](https://github.com/sysnet4admin/_Lecture_k8s_learning.kit). Vendored here so the benchmark can own the cluster configuration independently (resource sizing, add-ons, version pins) without modifying the upstream teaching repository.

## Specs

| Component | Value |
|---|---|
| Kubernetes | v1.35.4 |
| Containerd | 2.2.2 (Ubuntu 24.04 Noble) |
| CNI | Calico |
| Load balancer | MetalLB (L2 mode, pool `192.168.1.161-199`) |
| Gateway | NGINX Gateway Fabric v2.3.0 |
| Storage | CSI NFS + default StorageClass |
| Metrics | metrics-server v0.8.0 |

| Node | vCPU | RAM | Private IP |
|---|---|---|---|
| cp-k8s | 2 | 4 GB | 192.168.1.150 |
| w1-k8s | 2 | 4 GB | 192.168.1.151 |
| w2-k8s | 2 | 4 GB | 192.168.1.152 |
| w3-k8s | 2 | 4 GB | 192.168.1.153 |

Total host footprint: 8 vCPU, 16 GB RAM.

## Prerequisites

- macOS host with **VirtualBox** + **Vagrant**
- `sysnet4admin/Ubuntu-k8s` box v1.0.0 (auto-fetched on first `vagrant up`)
- Available host ports 60010–60013 (SSH forwarding)

## Lifecycle

```bash
./up.sh                    # provision + wait for MetalLB ready (~20–25 min first time)
./snapshot.sh              # save baseline snapshot (run once after up.sh completes)
./status.sh                # quick health check
./reset.sh                 # restore baseline snapshot (fast, ~30–60s)
./snapshot.sh my-checkpoint  # save named snapshot
./down.sh                  # destroy all VMs (with confirmation prompt)
```

## kubectl context

Context name: **`AIOps-Agent-Benchmark`**

After `up.sh` completes the first time, import the kubeconfig:

```bash
# fetch admin.conf, rename cluster/user/context, merge into ~/.kube/config
# (see kubeconfig setup in GUIDANCE.md §Operations)
```

## Reset strategy

Scenarios must start from a known-good state. Workflow:

1. `./snapshot.sh` once after initial provisioning → creates `baseline`
2. Before each scenario run: `./reset.sh` → back to baseline in ~30s
3. During scenario development: `./snapshot.sh <name>` for intermediate checkpoints

## Notes

- `extra_k8s_pkgs.sh` backgrounds `sleep 540` and `sleep 600` calls to apply MetalLB L2 config + IP range after CRDs settle. `up.sh` polls for the final `IPAddressPool` resource as the readiness signal.
- The cluster uses a private VirtualBox network (`192.168.1.0/24`). Do not connect to any real Wi-Fi/LAN with overlapping subnet or routing will break.
