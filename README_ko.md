# Research

[English](README.md)

Kubernetes, 클라우드 네이티브, AI에 대한 벤치마크 및 PoC 연구 저장소, [kuberneteslab.dev](https://kuberneteslab.dev/ko/)의 연구 기반입니다.

---

## 소개

**[KubernetesLab](https://kuberneteslab.dev/ko/)** 은 Kubernetes, 클라우드 네이티브, AI를 주제로 한 연구, 컨설팅, 교육 플랫폼입니다. 이 저장소의 각 프로젝트는 직접 실험한 연구 결과이며 블로그 포스트로 발행됩니다. 연구는 세 가지 영역을 다룹니다:

- **AI / AIOps**: 실제 Kubernetes 운영 및 장애 대응 과제에서 AI 코딩 에이전트, 오픈 웨이트 모델, 에이전트 하네스 비교
- **에이전트 프로토콜**: MCP 와 A2A, 그리고 그 앞의 게이트웨이가 실제로 무엇을 강제하고 관측하며 얼마를 쓰는지 스펙이 아니라 실측으로 확인
- **Kubernetes**: Gateway API 구현체 비교, CNI 상시 자원 비용, 클러스터 최적화, 관측 가능성
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

CNI 5종(Calico, Cilium, Flannel, Antrea, kube-router)의 상시 자원 비용을 14개 구성과 6개 부하 구간에서 9일 무인 측정합니다. CPU, 메모리, eBPF map 커널 메모리까지 수집했으며 조건을 가르는 축은 CPU가 아니라 메모리 사용량이라는 것과 kube-proxy를 nftables 모드로 바꾸는 것만으로 메모리 사용량이 70% 줄어든다는 것이 대표 결과입니다.

→ [블로그 포스트](https://kuberneteslab.dev/ko/blog/cni-standing-cost/) | [README (EN)](./cni-benchmark/README.md) | [README (KO)](./cni-benchmark/README_ko.md)

---

### [mcp-migration](./mcp-migration)

MCP 2026-07-28 스테이트리스 개정이 쿠버네티스 위의 서버에 무엇을 바꾸는지 측정합니다. 세션 기반 서버와 신 스펙으로 포팅한 서버에 같은 워크로드를 주고 스케일아웃, 파드 교체, 핸들 설계 3종을 비교했습니다. 구 스펙은 레플리카를 늘릴수록 처리량이 줄고 회차마다 달라지며(레플리카 4에서 중앙값 33.2rps, 요청 78,000건 중 세션 유실 37,844건), 신 스펙은 측정한 모든 조건에서 목표 처리량을 유지하고 핸들 상태를 파드 메모리에 둔 채 포팅하면 같은 실패가 HTTP 200 안에 도구 오류로 다시 나타난다는 것이 대표 결과입니다.

→ [블로그 포스트](https://kuberneteslab.dev/ko/blog/mcp-stateless-migration/) | [README (EN)](./mcp-migration/README.md) | [README (KO)](./mcp-migration/README_ko.md)

---

### [mcp-server-benchmark](./mcp-server-benchmark)

K8s용 MCP 서버 6종을 한 자에 올려 비교합니다. 프로브 모델, 장애 시나리오 10개, 하네스, 클러스터, 채점기를 전부 고정하고 MCP 서버만 교체해 240런을 돌렸습니다. MCP 서버를 꽂는 것이 공짜 품질이 아니라는 것(6종 중 4종이 셸 기준선 0.9167보다 낮습니다), 범용 서버는 예외 없이 셸보다 토큰을 더 쓴다는 것(도구 정의가 컨텍스트에 실립니다)이 대표 결과입니다. 상위 두 종은 접전이라 점수가 아니라 비용으로 고르는 편이 낫습니다.

→ [README (EN)](./mcp-server-benchmark/README.md) | [README (KO)](./mcp-server-benchmark/README_ko.md)

---

### [agentgateway-study](./agentgateway-study)

agentgateway(v1.5.0, Kubernetes 1.37. 첫 회차는 v1.4.1)가 MCP 앞단에서 문서에 적힌 대로 강제하고 관측하는지를 실측합니다. 도구 인자 조건을 쓴 인가 정책이 검증을 통과한 채 모든 호출을 막는다는 것(업스트림 #3092로 제보), 정책은 접두사가 붙기 전의 원래 이름을 평가한다는 것, traceparent가 헤더와 `_meta` 양쪽으로 전파된다는 것, 게이트웨이 비용이 도구 호출당 p50 1ms 아래이고 어떤 백엔드 처리 시간에서도 꼬리 지연을 낮추지는 않는다는 것, 화이트리스트로 `tools/list`를 거르는 비용은 게이트웨이에서 0이지만 지연을 줄여 주지도 않는다는 것이 대표 결과입니다. A2A 표면(카드 주소 변경, A2A 인가 없음)은 같은 연구의 한 절입니다.

→ [README (EN)](./agentgateway-study/README.md) | [README (KO)](./agentgateway-study/README_ko.md)

---

### [agentgateway-study/a2a](./agentgateway-study/a2a)

agentgateway(v1.5.0)가 A2A 에이전트 앞단에서 실제로 강제하고 관측하는 것을 실측합니다. 에이전트 카드의 주소 변경이 옵트인이고 병기 형식 카드(v0.3 `url` + v1.0 `supportedInterfaces`, 공식 파이썬 SDK의 기본)는 스위치를 켜도 직접 주소를 내보내 v0.3 클라이언트가 게이트웨이를 우회한다는 것, A2A 표면에는 요청 인가 정책이 없다는 것(강제 없는 관측), JSON-RPC 오류가 HTTP 200에 실리지만 액세스 로그에는 남는다는 것, 게이트웨이 홉 비용이 연결 방식에 따라 p50 +0.8~3.0ms이고 A2A 프로토콜 처리 자체는 +0.0~0.2ms라는 것이 대표 결과입니다.

→ [README (EN)](./agentgateway-study/a2a/README.md) | [README (KO)](./agentgateway-study/a2a/README_ko.md)

---

### [a2a-study](./a2a-study)

A2A가 스펙에 무엇이라 적혀 있는지가 아니라 어떤 상황에서 실제로 쓸모가 있는지를 묻습니다. 1단계에서 셋을 쟀습니다. 스펙이 선언한 것 대 공식 SDK의 기본 동작, 같은 작업을 넘길 때 MCP 및 순수 HTTP와의 비교, 그리고 프로토콜 자체의 비용입니다. 2단계는 두 세대 사이의 상호운용과 게이트웨이 통과를 다룹니다. 위의 agentgateway A2A 표면과는 별개 연구입니다. 그쪽은 게이트웨이가 무엇을 강제하는지를 재고 이쪽은 프로토콜 자체를 잽니다.

→ [README (EN)](./a2a-study/README.md) | [README (KO)](./a2a-study/README_ko.md)

---

## 작성자

**조훈 (Hoon Jo)** / CNCF Ambassador / AAIF Ambassador / Kubestronaut / [@sysnet4admin](https://github.com/sysnet4admin) / [kuberneteslab.dev](https://kuberneteslab.dev/ko/)
