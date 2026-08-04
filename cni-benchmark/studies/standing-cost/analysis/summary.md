# 집계 결과 (반복 간 중앙값, 클러스터 합)

## 조건 x 페이즈: 네트워킹 스택 총합 (CNI + kube-proxy)

값 = CPU mC / working set MiB. bpf = eBPF map memlock MiB.

| 조건 | 반복 | idle | density | policy | service | churn | node | idle bpf |
|---|---|---|---|---|---|---|---|---|
| A1 | 5 | 60 / 758 | 60 / 769 | 60 / 788 | 61 / 954 | 285 / 1101 | 66 / 1108 | 0.0 |
| A2 | 3 | 50 / 762 | 54 / 774 | 53 / 792 | 53 / 955 | 284 / 1108 | 60 / 1115 | 0.0 |
| C1 | 6 | 84 / 1005 | 84 / 1016 | 87 / 1033 | 93 / 1163 | 418 / 1319 | 110 / 1233 | 3.0 |
| C2 | 6 | 87 / 920 | 86 / 933 | 96 / 962 | 88 / 1029 | 185 / 1096 | 87 / 1044 | 520.9 |
| C3 | 6 | 80 / 472 | 77 / 481 | 80 / 495 | 92 / 614 | 468 / 748 | 118 / 714 | 3.0 |
| C4 | 6 | 84 / 1077 | 83 / 1087 | 88 / 1105 | 95 / 1249 | 445 / 1458 | 112 / 1340 | 3.0 |
| F1 | 5 | 24 / 319 | 24 / 320 | 22 / 320 | 23 / 410 | 193 / 509 | 28 / 492 | 0.0 |
| F1n | 5 | 23 / 209 | 22 / 209 | 22 / 209 | 21 / 248 | 147 / 323 | 24 / 277 | 0.0 |
| K1 | 5 | 2 / 215 | 4 / 232 | 14 / 262 | 77 / 315 | 3355 / 1159 | 3158 / 1503 | 0.0 |
| K2 | 5 | 3 / 369 | 5 / 385 | 15 / 418 | 6 / 538 | 406 / 676 | 25 / 626 | 0.0 |
| X1 | 6 | 110 / 1574 | 114 / 1639 | 116 / 1657 | 115 / 1795 | 279 / 2003 | 119 / 1943 | 411.8 |
| X2 | 5 | 116 / 1551 | 114 / 1605 | 116 / 1627 | 115 / 1763 | 280 / 1963 | 120 / 1907 | 411.8 |
| X3 | 5 | 123 / 1705 | 129 / 1761 | 129 / 1783 | 127 / 1826 | 131 / 1926 | 126 / 1894 | 711.8 |
| X4 | 5 | 127 / 1705 | 130 / 1759 | 131 / 1778 | 129 / 1823 | 133 / 1927 | 128 / 1892 | 711.8 |

## 조건별 구성 요소 상세 (idle)

### A1 (반복 5회)

| 구성 요소 | 분류 | CPU mC | ws MiB | rss MiB |
|---|---|---|---|---|
| antrea-agent | cni | 52.97 | 504.1 | 230.1 |
| antrea-controller | cni | 5.56 | 95.8 | 33.0 |
| coredns | control | 3.81 | 24.3 | 22.5 |
| etcd | control | 31.37 | 83.9 | 43.3 |
| kube-apiserver | control | 62.69 | 357.5 | 282.6 |
| kube-controller-manager | control | 19.77 | 109.7 | 49.9 |
| kube-scheduler | control | 11.33 | 61.7 | 21.8 |
| kube-proxy | proxy | 1.01 | 158.1 | 33.8 |
| **스택 총합** | cni+proxy | **59.5** | **758.0** | |
| eBPF map | kernel | | 0.0 | |

### A2 (반복 3회)

| 구성 요소 | 분류 | CPU mC | ws MiB | rss MiB |
|---|---|---|---|---|
| antrea-agent | cni | 44.74 | 508.7 | 230.3 |
| antrea-controller | cni | 4.7 | 96.0 | 33.2 |
| coredns | control | 3.69 | 24.0 | 22.7 |
| etcd | control | 24.99 | 84.6 | 44.1 |
| kube-apiserver | control | 49.03 | 359.8 | 284.7 |
| kube-controller-manager | control | 13.32 | 109.4 | 49.4 |
| kube-scheduler | control | 7.67 | 62.0 | 21.4 |
| kube-proxy | proxy | 0.77 | 157.7 | 33.6 |
| **스택 총합** | cni+proxy | **50.2** | **762.4** | |
| eBPF map | kernel | | 0.0 | |

### C1 (반복 6회)

| 구성 요소 | 분류 | CPU mC | ws MiB | rss MiB |
|---|---|---|---|---|
| calico-apiserver | cni | 5.72 | 147.35 | 81.15 |
| calico-kube-controllers | cni | 1.19 | 99.95 | 29.6 |
| calico-node | cni | 66.53 | 226.65 | 120.45 |
| calico-typha | cni | 5.46 | 131.9 | 34.9 |
| csi-node-driver | cni | 0.15 | 97.85 | 16.8 |
| tigera-operator | cni | 4.37 | 143.2 | 82.5 |
| coredns | control | 3.6 | 75.3 | 22.7 |
| etcd | control | 34.83 | 86.9 | 45.85 |
| kube-apiserver | control | 71.08 | 493.1 | 417.5 |
| kube-controller-manager | control | 19.66 | 115.35 | 55.2 |
| kube-scheduler | control | 11.25 | 62.4 | 22.3 |
| kube-proxy | proxy | 0.96 | 158.3 | 34.05 |
| **스택 총합** | cni+proxy | **84.4** | **1005.2** | |
| eBPF map | kernel | | 3.0 | |

### C2 (반복 6회)

| 구성 요소 | 분류 | CPU mC | ws MiB | rss MiB |
|---|---|---|---|---|
| calico-apiserver | cni | 5.76 | 147.55 | 81.55 |
| calico-kube-controllers | cni | 1.4 | 99.55 | 29.0 |
| calico-node | cni | 70.19 | 298.85 | 181.05 |
| calico-typha | cni | 5.46 | 133.05 | 35.6 |
| csi-node-driver | cni | 0.16 | 97.7 | 16.7 |
| tigera-operator | cni | 4.3 | 143.8 | 82.55 |
| coredns | control | 4.05 | 24.35 | 22.85 |
| etcd | control | 34.84 | 87.2 | 46.05 |
| kube-apiserver | control | 72.31 | 492.35 | 416.3 |
| kube-controller-manager | control | 20.29 | 114.85 | 55.15 |
| kube-scheduler | control | 11.6 | 62.3 | 22.1 |
| **스택 총합** | cni+proxy | **87.3** | **920.5** | |
| eBPF map | kernel | | 520.9 | |

### C3 (반복 6회)

| 구성 요소 | 분류 | CPU mC | ws MiB | rss MiB |
|---|---|---|---|---|
| calico-kube-controllers | cni | 2.78 | 91.5 | 21.0 |
| calico-node | cni | 76.61 | 222.35 | 116.15 |
| coredns | control | 3.76 | 24.1 | 22.4 |
| etcd | control | 28.1 | 83.5 | 42.8 |
| kube-apiserver | control | 54.52 | 367.25 | 292.3 |
| kube-controller-manager | control | 16.3 | 109.3 | 49.4 |
| kube-scheduler | control | 8.32 | 62.05 | 21.65 |
| kube-proxy | proxy | 0.84 | 158.65 | 33.35 |
| **스택 총합** | cni+proxy | **80.2** | **472.5** | |
| eBPF map | kernel | | 3.0 | |

### C4 (반복 6회)

| 구성 요소 | 분류 | CPU mC | ws MiB | rss MiB |
|---|---|---|---|---|
| calico-apiserver | cni | 5.6 | 147.0 | 80.9 |
| calico-kube-controllers | cni | 1.21 | 99.9 | 29.1 |
| calico-node | cni | 66.5 | 295.35 | 173.0 |
| calico-typha | cni | 5.61 | 134.3 | 36.25 |
| csi-node-driver | cni | 0.15 | 97.9 | 16.8 |
| tigera-operator | cni | 4.03 | 143.7 | 82.9 |
| coredns | control | 3.77 | 75.0 | 22.6 |
| etcd | control | 32.55 | 87.0 | 46.05 |
| kube-apiserver | control | 67.02 | 494.05 | 418.6 |
| kube-controller-manager | control | 19.09 | 115.2 | 55.2 |
| kube-scheduler | control | 9.58 | 62.5 | 22.2 |
| kube-proxy | proxy | 0.88 | 158.55 | 34.05 |
| **스택 총합** | cni+proxy | **84.0** | **1076.7** | |
| eBPF map | kernel | | 3.0 | |

### F1 (반복 5회)

| 구성 요소 | 분류 | CPU mC | ws MiB | rss MiB |
|---|---|---|---|---|
| kube-flannel-ds | cni | 23.08 | 161.5 | 31.4 |
| coredns | control | 4.62 | 23.8 | 22.5 |
| etcd | control | 27.22 | 76.8 | 36.3 |
| kube-apiserver | control | 53.44 | 290.6 | 216.0 |
| kube-controller-manager | control | 18.83 | 104.8 | 44.8 |
| kube-scheduler | control | 11.7 | 61.0 | 21.0 |
| kube-proxy | proxy | 1.06 | 157.5 | 33.4 |
| **스택 총합** | cni+proxy | **24.1** | **319.0** | |
| eBPF map | kernel | | 0.0 | |

### F1n (반복 5회)

| 구성 요소 | 분류 | CPU mC | ws MiB | rss MiB |
|---|---|---|---|---|
| kube-flannel-ds | cni | 22.29 | 161.8 | 31.9 |
| coredns | control | 4.47 | 23.9 | 22.6 |
| etcd | control | 27.92 | 77.1 | 36.7 |
| kube-apiserver | control | 54.48 | 291.1 | 216.9 |
| kube-controller-manager | control | 20.09 | 105.3 | 45.5 |
| kube-scheduler | control | 9.58 | 61.3 | 21.1 |
| kube-proxy | proxy | 0.67 | 46.8 | 33.4 |
| **스택 총합** | cni+proxy | **23.0** | **208.6** | |
| eBPF map | kernel | | 0.0 | |

### K1 (반복 5회)

| 구성 요소 | 분류 | CPU mC | ws MiB | rss MiB |
|---|---|---|---|---|
| kube-router | cni | 2.51 | 214.8 | 66.5 |
| coredns | control | 4.51 | 24.0 | 22.5 |
| etcd | control | 27.72 | 77.3 | 36.9 |
| kube-apiserver | control | 54.14 | 285.7 | 211.6 |
| kube-controller-manager | control | 20.1 | 105.4 | 45.4 |
| kube-scheduler | control | 11.39 | 61.0 | 21.1 |
| **스택 총합** | cni+proxy | **2.5** | **214.8** | |
| eBPF map | kernel | | 0.0 | |

### K2 (반복 5회)

| 구성 요소 | 분류 | CPU mC | ws MiB | rss MiB |
|---|---|---|---|---|
| kube-router | cni | 2.31 | 211.6 | 65.2 |
| coredns | control | 4.59 | 24.2 | 22.9 |
| etcd | control | 28.01 | 77.1 | 36.7 |
| kube-apiserver | control | 54.7 | 285.7 | 211.8 |
| kube-controller-manager | control | 17.83 | 106.0 | 45.2 |
| kube-scheduler | control | 10.93 | 61.1 | 20.9 |
| kube-proxy | proxy | 1.04 | 157.7 | 33.5 |
| **스택 총합** | cni+proxy | **3.4** | **369.3** | |
| eBPF map | kernel | | 0.0 | |

### X1 (반복 6회)

| 구성 요소 | 분류 | CPU mC | ws MiB | rss MiB |
|---|---|---|---|---|
| cilium | cni | 94.73 | 1137.0 | 236.1 |
| cilium-envoy | cni | 9.38 | 167.0 | 41.0 |
| cilium-operator | cni | 4.62 | 111.4 | 29.45 |
| coredns | control | 3.89 | 24.0 | 22.7 |
| etcd | control | 29.39 | 81.85 | 41.0 |
| kube-apiserver | control | 57.92 | 367.55 | 292.75 |
| kube-controller-manager | control | 17.87 | 109.2 | 49.35 |
| kube-scheduler | control | 9.22 | 62.55 | 22.3 |
| kube-proxy | proxy | 0.9 | 158.85 | 34.0 |
| **스택 총합** | cni+proxy | **109.6** | **1574.2** | |
| eBPF map | kernel | | 411.8 | |

### X2 (반복 5회)

| 구성 요소 | 분류 | CPU mC | ws MiB | rss MiB |
|---|---|---|---|---|
| cilium | cni | 100.89 | 1115.2 | 215.3 |
| cilium-envoy | cni | 9.57 | 166.9 | 40.9 |
| cilium-operator | cni | 4.7 | 110.9 | 29.2 |
| coredns | control | 3.65 | 24.0 | 22.6 |
| etcd | control | 31.14 | 82.2 | 41.4 |
| kube-apiserver | control | 62.29 | 364.9 | 290.4 |
| kube-controller-manager | control | 19.05 | 109.7 | 49.6 |
| kube-scheduler | control | 10.0 | 62.3 | 22.0 |
| kube-proxy | proxy | 0.99 | 158.3 | 33.4 |
| **스택 총합** | cni+proxy | **116.2** | **1551.3** | |
| eBPF map | kernel | | 411.8 | |

### X3 (반복 5회)

| 구성 요소 | 분류 | CPU mC | ws MiB | rss MiB |
|---|---|---|---|---|
| cilium | cni | 107.99 | 1426.5 | 223.5 |
| cilium-envoy | cni | 9.67 | 167.0 | 40.9 |
| cilium-operator | cni | 5.23 | 111.2 | 29.3 |
| coredns | control | 3.72 | 74.6 | 22.8 |
| etcd | control | 30.62 | 81.9 | 41.1 |
| kube-apiserver | control | 62.65 | 366.9 | 292.1 |
| kube-controller-manager | control | 19.87 | 109.5 | 49.1 |
| kube-scheduler | control | 11.69 | 62.3 | 21.9 |
| **스택 총합** | cni+proxy | **122.9** | **1704.7** | |
| eBPF map | kernel | | 711.8 | |

### X4 (반복 5회)

| 구성 요소 | 분류 | CPU mC | ws MiB | rss MiB |
|---|---|---|---|---|
| cilium | cni | 111.61 | 1427.0 | 223.8 |
| cilium-envoy | cni | 9.87 | 166.9 | 40.9 |
| cilium-operator | cni | 5.25 | 111.3 | 29.4 |
| coredns | control | 4.76 | 24.0 | 22.7 |
| etcd | control | 31.06 | 82.2 | 41.4 |
| kube-apiserver | control | 62.4 | 364.3 | 289.5 |
| kube-controller-manager | control | 20.33 | 109.1 | 49.6 |
| kube-scheduler | control | 11.91 | 62.0 | 22.0 |
| **스택 총합** | cni+proxy | **126.7** | **1705.2** | |
| eBPF map | kernel | | 711.8 | |
