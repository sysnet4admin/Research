# test-cluster (agents-md-migration)

이 연구 전용 Kubernetes 클러스터. AIOps 벤치마크 클러스터와 **완전히 격리**된다.
컨트롤플레인 1 + 워커 1(2노드)만 띄운다. 이 실험은 스케줄 가능한 노드 하나면 충분하다.

## AIOps 클러스터와의 격리

| 항목 | 이 클러스터 | AIOps |
|---|---|---|
| 서브넷 | **192.168.2.0/24** | 192.168.1.0/24 |
| VBox 그룹 | `/agents-md-migration` | `/AIOps-Agent-Benchmark` |
| VM 이름 접미사 | `-agentsmd` | `-aiops-bench` |
| ssh 포워딩 | 60160 / 60161 | 60150~60153 |
| kubectl 컨텍스트 | `agents-md-migration` | `AIOps-Agent-Benchmark` |
| K8s 버전 | **v1.36.2** (상향) | v1.36.0 |

IP와 이름, 그룹이 겹치지 않아 두 클러스터가 동시에 떠 있어도 충돌하지 않는다.

## Provenance

프로비저닝 로직은 AIOps `test-cluster/`에서 가져와 이 연구용으로 격리 파라미터만 바꿨다
(원출처: [sysnet4admin/_Lecture_k8s_learning.kit/B/B.001/U](https://github.com/sysnet4admin/_Lecture_k8s_learning.kit)).
시나리오를 그대로 재사용하므로 애드온(MetalLB/NGF/metrics-server/CSI-NFS)도 AIOps와 동일하게 설치한다.

## Specs

| Component | Value |
|---|---|
| Kubernetes | v1.36.2 |
| Containerd | 2.2.3 (Ubuntu 24.04 Noble) |
| CNI | Calico v3.31.2 |
| Load balancer | MetalLB (L2 mode, pool `192.168.2.200-220`) |
| Gateway | NGINX Gateway Fabric v2.3.0 |
| Storage | CSI NFS + default StorageClass |
| Metrics | metrics-server v0.8.0 |

| Node | vCPU | RAM | Private IP |
|---|---|---|---|
| cp-k8s | 2 | 4 GB | 192.168.2.10 |
| w1-k8s | 2 | 4 GB | 192.168.2.11 |

Total host footprint: 4 vCPU, 8 GB RAM.

## Prerequisites

- macOS host with **VirtualBox** + **Vagrant**
- `sysnet4admin/Ubuntu-k8s` box (auto-fetched on first `vagrant up`)
- 호스트 포트 60160/60161 사용 가능
- VirtualBox host-only 네트워크가 192.168.2.0/24를 허용해야 한다(`/etc/vbox/networks.conf`에
  `192.168.0.0/16` 규칙이 있으면 됨. AIOps가 192.168.1.x를 이미 쓰므로 대개 이미 허용 상태).

## Lifecycle

```bash
./up.sh                      # provision + wait for MetalLB ready (first time ~20 min)
./snapshot.sh                # save baseline snapshot (run once after up.sh completes)
./status.sh                  # quick health check
./reset.sh                   # restore baseline snapshot (fast)
./down.sh                    # destroy all VMs (confirmation prompt)
```

## audit 로깅 (unsafe_actions 채점용)

이 연구도 결정론 safety 채점(감사 로그 기반)을 재사용한다. `up.sh` 후 한 번:

```bash
vagrant scp audit-policy.yaml cp-k8s-1.36.2:/tmp/audit-policy.yaml   # 또는 ssh로 업로드
vagrant ssh cp-k8s-1.36.2 -c "sudo bash /vagrant_scripts/enable-audit.sh"  # 경로는 배치에 맞게
./snapshot.sh baseline       # audit 켠 상태를 baseline에 포함
```

## kubectl context

컨텍스트명 **`agents-md-migration`**. `up.sh` 최초 완료 후 admin.conf를 받아
cluster/user/context 이름을 위 컨텍스트명으로 바꿔 `~/.kube/config`에 병합한다.

## 버전 메모

- v1.36.2는 2026-06-09 릴리스된 1.36 계열 최신 패치다(AIOps 1.36.0 대비 상향).
- v1.37.0은 2026-08-26 예정이라 아직 GA가 아니다. GA 후 상향하려면 `Vagrantfile`의 `k8s_V`와
  `config.sh`의 VM 이름 접미사(`k8s_V[0..5]`)만 함께 바꾼다.
