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

## 작성자

**조훈 (Hoon Jo)** / CNCF Ambassador / Kubestronaut / [@sysnet4admin](https://github.com/sysnet4admin) / [kuberneteslab.dev](https://kuberneteslab.dev/ko/)
