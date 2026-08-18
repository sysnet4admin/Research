# mcp-migration test-cluster

MCP 2026-07-28 stateless 전환 실측 전용 클러스터. agents-md-migration `test-cluster/`를
적응(그쪽은 [sysnet4admin/_Lecture_k8s_learning.kit](https://github.com/sysnet4admin/_Lecture_k8s_learning.kit) 파생).

| 항목 | 값 |
|---|---|
| K8s | v1.36.2 (패키지 리비전 `1.36.2-2.1`) |
| CNI | Calico v3.31.2 |
| Load balancer | MetalLB v0.15.3 (L2, pool `192.168.2.230-250`) |
| 노드 | cp-k8s `.150`, w1-k8s `.151`, w2-k8s `.152` (2 CPU / 4GB each) |
| VBox | 그룹 `/mcp-migration`, VM 접미사 `-mcpmig`, ssh 60250~60252 |
| kubectl 컨텍스트 | `mcp-migration` |

agents-md 대비 차이: 워커 2개(스케일아웃/재스케줄 측정), audit 없음, NFS/스토리지 없음,
NGF 미포함(측정 경로 b는 격리 캠페인으로 설치), metrics-server 유지.

## 사용

```bash
./up.sh        # 기동 + MetalLB 준비 대기
./status.sh    # VM/노드/스냅샷 상태
./snapshot.sh  # baseline 스냅샷 (halt 후 저장)
./reset.sh     # baseline 복원
./down.sh      # 전체 파기
```

kubeconfig 병합(최초 1회): 클러스터 기동 후 admin.conf를 가져와 컨텍스트
`mcp-migration`으로 병합한다. 모든 kubectl은 `--context mcp-migration` 명시.
