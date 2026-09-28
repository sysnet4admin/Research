# 집계 결과 (반복 간 중앙값, 클러스터 합)

## 조건 x 페이즈: 네트워킹 스택 총합 (CNI + kube-proxy)

값 = CPU mC / working set MiB. bpf = eBPF map memlock MiB.

| 조건 | 반복 | idle | density | policy | service | churn | node | idle bpf |
|---|---|---|---|---|---|---|---|---|
| A1 | 3 | 60 / 676 | 60 / 689 | 59 / 706 | 60 / 880 | 287 / 1024 | 68 / 1035 | 0.0 |
| A2 | 3 | 67 / 681 | 65 / 695 | 66 / 713 | 65 / 880 | 290 / 1030 | 72 / 1032 | 0.0 |
| K1 | 3 | 3 / 70 | 5 / 87 | 15 / 117 | 31 / 170 | 2268 / 222 | 59 / 201 | 0.0 |
| K2 | 3 | 4 / 227 | 5 / 242 | 15 / 275 | 7 / 394 | 396 / 531 | 23 / 482 | 0.0 |
| X1 | 3 | 112 / 1596 | 117 / 1674 | 119 / 1701 | 117 / 1834 | 273 / 2056 | 121 / 1986 | 412.1 |
| X2 | 3 | 112 / 1575 | 114 / 1640 | 116 / 1663 | 115 / 1798 | 271 / 2012 | 120 / 1937 | 412.1 |
| X3 | 3 | 124 / 1732 | 125 / 1796 | 128 / 1823 | 126 / 1861 | 131 / 1984 | 126 / 1936 | 715.1 |
| X4 | 3 | 117 / 1734 | 119 / 1798 | 122 / 1824 | 119 / 1860 | 129 / 1984 | 120 / 1934 | 715.1 |

## 조건별 구성 요소 상세 (idle)

### A1 (반복 3회)

| 구성 요소 | 분류 | CPU mC | ws MiB | rss MiB |
|---|---|---|---|---|
| antrea-agent | cni | 52.6 | 419.6 | 138.2 |
| antrea-controller | cni | 6.63 | 97.9 | 33.1 |
| coredns | control | 4.92 | 24.1 | 22.8 |
| etcd | control | 30.18 | 84.4 | 43.8 |
| kube-apiserver | control | 60.97 | 360.3 | 285.4 |
| kube-controller-manager | control | 18.87 | 110.1 | 50.0 |
| kube-scheduler | control | 12.06 | 61.5 | 21.4 |
| kube-proxy | proxy | 1.11 | 159.0 | 33.9 |
| **스택 총합** | cni+proxy | **60.3** | **676.5** | |
| eBPF map | kernel | | 0.0 | |

### A2 (반복 3회)

| 구성 요소 | 분류 | CPU mC | ws MiB | rss MiB |
|---|---|---|---|---|
| antrea-agent | cni | 60.15 | 424.4 | 139.3 |
| antrea-controller | cni | 5.93 | 97.4 | 33.0 |
| coredns | control | 4.38 | 74.5 | 22.6 |
| etcd | control | 30.52 | 84.5 | 43.8 |
| kube-apiserver | control | 62.34 | 358.6 | 283.7 |
| kube-controller-manager | control | 19.36 | 109.7 | 50.0 |
| kube-scheduler | control | 11.75 | 61.5 | 21.5 |
| kube-proxy | proxy | 1.03 | 159.1 | 33.7 |
| **스택 총합** | cni+proxy | **67.1** | **680.9** | |
| eBPF map | kernel | | 0.0 | |

### K1 (반복 3회)

| 구성 요소 | 분류 | CPU mC | ws MiB | rss MiB |
|---|---|---|---|---|
| kube-router | cni | 2.95 | 69.9 | 66.2 |
| coredns | control | 4.76 | 74.5 | 22.5 |
| etcd | control | 27.17 | 77.4 | 36.9 |
| kube-apiserver | control | 53.1 | 291.5 | 217.7 |
| kube-controller-manager | control | 18.52 | 105.7 | 45.6 |
| kube-scheduler | control | 12.38 | 61.3 | 21.0 |
| **스택 총합** | cni+proxy | **3.0** | **69.9** | |
| eBPF map | kernel | | 0.0 | |

### K2 (반복 3회)

| 구성 요소 | 분류 | CPU mC | ws MiB | rss MiB |
|---|---|---|---|---|
| kube-router | cni | 2.68 | 69.4 | 66.2 |
| coredns | control | 4.86 | 23.8 | 22.5 |
| etcd | control | 26.4 | 77.8 | 37.3 |
| kube-apiserver | control | 53.27 | 289.6 | 215.8 |
| kube-controller-manager | control | 17.55 | 105.9 | 45.8 |
| kube-scheduler | control | 12.38 | 61.3 | 20.9 |
| kube-proxy | proxy | 1.11 | 157.4 | 33.1 |
| **스택 총합** | cni+proxy | **3.8** | **226.8** | |
| eBPF map | kernel | | 0.0 | |

### X1 (반복 3회)

| 구성 요소 | 분류 | CPU mC | ws MiB | rss MiB |
|---|---|---|---|---|
| cilium | cni | 92.94 | 1145.6 | 234.4 |
| cilium-envoy | cni | 9.18 | 170.1 | 40.0 |
| cilium-operator | cni | 8.91 | 121.2 | 32.7 |
| coredns | control | 4.85 | 24.0 | 22.6 |
| etcd | control | 29.94 | 82.0 | 41.3 |
| kube-apiserver | control | 60.63 | 371.0 | 295.9 |
| kube-controller-manager | control | 18.7 | 109.6 | 49.8 |
| kube-scheduler | control | 11.76 | 62.4 | 22.1 |
| kube-proxy | proxy | 1.09 | 158.9 | 33.9 |
| **스택 총합** | cni+proxy | **112.1** | **1595.8** | |
| eBPF map | kernel | | 412.1 | |

### X2 (반복 3회)

| 구성 요소 | 분류 | CPU mC | ws MiB | rss MiB |
|---|---|---|---|---|
| cilium | cni | 93.0 | 1126.1 | 215.2 |
| cilium-envoy | cni | 9.24 | 170.1 | 40.0 |
| cilium-operator | cni | 8.76 | 120.2 | 32.3 |
| coredns | control | 4.81 | 24.1 | 22.8 |
| etcd | control | 29.54 | 82.4 | 41.6 |
| kube-apiserver | control | 61.25 | 369.0 | 294.2 |
| kube-controller-manager | control | 19.21 | 110.2 | 49.9 |
| kube-scheduler | control | 11.89 | 62.6 | 22.2 |
| kube-proxy | proxy | 1.03 | 158.7 | 33.7 |
| **스택 총합** | cni+proxy | **112.0** | **1575.1** | |
| eBPF map | kernel | | 412.1 | |

### X3 (반복 3회)

| 구성 요소 | 분류 | CPU mC | ws MiB | rss MiB |
|---|---|---|---|---|
| cilium | cni | 106.74 | 1440.7 | 222.3 |
| cilium-envoy | cni | 9.58 | 170.0 | 39.9 |
| cilium-operator | cni | 8.17 | 121.3 | 32.5 |
| coredns | control | 4.82 | 24.0 | 22.7 |
| etcd | control | 29.66 | 81.5 | 40.6 |
| kube-apiserver | control | 60.44 | 367.3 | 292.3 |
| kube-controller-manager | control | 19.3 | 109.8 | 49.5 |
| kube-scheduler | control | 12.14 | 62.2 | 22.1 |
| **스택 총합** | cni+proxy | **124.5** | **1732.0** | |
| eBPF map | kernel | | 715.1 | |

### X4 (반복 3회)

| 구성 요소 | 분류 | CPU mC | ws MiB | rss MiB |
|---|---|---|---|---|
| cilium | cni | 98.86 | 1442.0 | 222.4 |
| cilium-envoy | cni | 9.49 | 170.1 | 40.0 |
| cilium-operator | cni | 8.97 | 121.4 | 32.4 |
| coredns | control | 5.18 | 24.0 | 22.7 |
| etcd | control | 30.16 | 81.8 | 41.0 |
| kube-apiserver | control | 60.84 | 367.1 | 292.1 |
| kube-controller-manager | control | 18.62 | 110.1 | 50.2 |
| kube-scheduler | control | 12.06 | 62.4 | 22.2 |
| **스택 총합** | cni+proxy | **117.3** | **1733.5** | |
| eBPF map | kernel | | 715.1 | |
