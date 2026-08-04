# cni-benchmark test-cluster

CNI 상시 자원 비용 측정 전용. **CNI를 설치하지 않는 베이스 클러스터**라는 점이
다른 클러스터와 다르다. 조건별 CNI는 `../studies/standing-cost/conditions/`가 올린다.

| 항목 | 값 |
|---|---|
| K8s | v1.36.2 (`1.36.2-2.1`), kubeadm, pod CIDR 172.16.0.0/16 |
| CNI | 없음 (베이스 스냅샷 시점 노드 NotReady = 정상) |
| Load balancer | 없음 (MetalLB 미설치, 측정 잡음 방지) |
| 노드 | cp-k8s `.50`, w1-k8s `.51`, w2-k8s `.52` (2 CPU / 4GB each) |
| VBox | 그룹 `/cni-benchmark`, 접미사 `-cnibench`, ssh 60350~60352 |
| kubectl 컨텍스트 | `cni-benchmark` |
| 추가 패키지 | helm, bpftool만 |

## 사용

```bash
./up.sh        # 기동 (노드 NotReady로 끝나는 것이 정상)
./status.sh
./snapshot.sh base-no-cni   # 프리페치 후 베이스 스냅샷
./reset.sh                  # base-no-cni 복원 (조건 전환마다)
./down.sh
```

베이스 스냅샷에는 조건 14개의 컨테이너 이미지가 전부 프리페치돼 있어야 한다
(무인 9일 동안 레지스트리 rate limit과 네트워크 의존을 없애기 위해).
프리페치는 `../studies/standing-cost/prefetch.sh`.
