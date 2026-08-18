# Research

[English](README.md)

Kubernetes, 클라우드 네이티브, AI에 대한 벤치마크 및 PoC 연구 저장소, [kuberneteslab.dev](https://kuberneteslab.dev/ko/)의 연구 기반입니다.

---

## 소개

**[KubernetesLab](https://kuberneteslab.dev/ko/)** 은 Kubernetes, 클라우드 네이티브, AI를 주제로 한 연구, 컨설팅, 교육 플랫폼입니다. 이 저장소의 각 프로젝트는 직접 실험한 연구 결과이며, 블로그 포스트로 발행됩니다. 연구는 세 가지 영역을 다룹니다:

- **AI / AIOps**: 실제 Kubernetes 운영 및 장애 대응 과제에서 AI 코딩 에이전트 성능 비교
- **Kubernetes**: Gateway API 구현체 비교, 클러스터 최적화, 관측 가능성
- **FinOps**: EKS/AKS 비용 절감 사례 연구 (각 49%, 48% 절감)

---

## 프로젝트

### [AIOps-Agent-Benchmark](./AIOps-Agent-Benchmark)

동일한 Kubernetes 장애 대응 시나리오에서 9개 AI 코딩 에이전트(Claude, Gemini, Codex)의 품질, 안전성, 효율을 비교합니다.

→ [블로그 포스트](https://kuberneteslab.dev/ko/blog/aiops-agent-benchmark/) | [README (EN)](./AIOps-Agent-Benchmark/README.md) | [README (KO)](./AIOps-Agent-Benchmark/README_ko.md) | [방법론](./AIOps-Agent-Benchmark/GUIDANCE.md)

---

### [gateway-PoC](./gateway-PoC)

7개 Kubernetes Gateway API 구현체를 라우팅, TLS, 트래픽 관리 등 17개 항목으로 100 라운드 반복 검증합니다.

→ [블로그 포스트](https://kuberneteslab.dev/ko/blog/gateway-api-comparison/) | [README (EN)](./gateway-PoC/README.md) | [README (KO)](./gateway-PoC/README_ko.md)

---

### [agents-md-migration](./agents-md-migration)

프로젝트 컨텍스트 파일을 CLAUDE.md에서 AGENTS.md로(import 또는 심볼릭 링크) 옮기면 Claude Code가 느려지거나 토큰 비용이 늘어나는지를 쿠버네티스 장애 대응 작업과 5개 모델 구성에서 측정합니다. 결과: 두 축 모두 페널티 없음.

→ [블로그 포스트](https://kuberneteslab.dev/ko/blog/agents-md-migration/) | [README (EN)](./agents-md-migration/README.md) | [README (KO)](./agents-md-migration/README_ko.md)

---

### [cni-benchmark](./cni-benchmark)

CNI 5종(Calico, Cilium, Flannel, Antrea, kube-router)의 상시 자원 비용을 14개 구성과 6개 부하 구간에서 9일 무인 측정합니다. CPU, 메모리, eBPF map 커널 메모리까지 수집했으며, 조건을 가르는 축은 CPU가 아니라 메모리 사용량이라는 것과 kube-proxy를 nftables 모드로 바꾸는 것만으로 메모리 사용량이 70% 줄어든다는 것이 대표 결과입니다.

→ [블로그 포스트](https://kuberneteslab.dev/ko/blog/cni-standing-cost/) | [README (EN)](./cni-benchmark/README.md) | [README (KO)](./cni-benchmark/README_ko.md)

---

### [mcp-migration](./mcp-migration)

MCP 2026-07-28 스테이트리스 개정이 쿠버네티스 위의 서버에 무엇을 바꾸는지 측정합니다. 세션 기반 서버와 신 스펙으로 포팅한 서버에 같은 워크로드를 주고 스케일아웃, 파드 교체, 핸들 설계 3종을 비교했습니다. 구 스펙은 레플리카를 늘릴수록 처리량이 줄고 회차마다 달라지며(레플리카 4에서 중앙값 33.2rps, 요청 78,000건 중 세션 유실 37,844건), 신 스펙은 측정한 모든 조건에서 목표 처리량을 유지하고, 핸들 상태를 파드 메모리에 둔 채 포팅하면 같은 실패가 HTTP 200 뒤에 숨어 재현된다는 것이 대표 결과입니다.

→ [블로그 포스트](https://kuberneteslab.dev/ko/blog/mcp-stateless-migration/) | [README (EN)](./mcp-migration/README.md) | [README (KO)](./mcp-migration/README_ko.md)

---

## 작성자

**조훈 (Hoon Jo)** / CNCF Ambassador / Kubestronaut / [@sysnet4admin](https://github.com/sysnet4admin) / [kuberneteslab.dev](https://kuberneteslab.dev/ko/)
