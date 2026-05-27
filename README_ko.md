# Research

[English](README.md)

Kubernetes, 클라우드 네이티브, AI에 대한 벤치마크 및 PoC 연구 저장소 — [kuberneteslab.dev](https://kuberneteslab.dev/ko/)의 연구 기반입니다.

---

## 소개

**[KubernetesLab](https://kuberneteslab.dev/ko/)** 은 Kubernetes, 클라우드 네이티브, AI를 주제로 한 연구·컨설팅·교육 플랫폼입니다. 이 저장소의 각 프로젝트는 직접 실험한 연구 결과이며, 블로그 포스트로 발행됩니다. 연구는 세 가지 영역을 다룹니다:

- **AI / AIOps** — 실제 Kubernetes 운영 및 장애 대응 과제에서 AI 코딩 에이전트 성능 비교
- **Kubernetes** — Gateway API 구현체 비교, 클러스터 최적화, 관측 가능성
- **FinOps** — EKS·AKS 비용 절감 사례 연구 (각 49%, 48% 절감)

---

## 프로젝트

### [AIOps-Agent-Benchmark](./AIOps-Agent-Benchmark)

동일한 Kubernetes 운영 및 장애 대응 시나리오에서 9개 AI 코딩 에이전트의 **품질, 안전성, 효율**을 측정하는 벤치마크입니다.

일반 코딩 벤치마크가 아니라 **AIOps / SRE 영역**(배포, 롤백, 장애 진단, 관측)에 특화됩니다. 9개 에이전트(3 브랜드 × 3 모델 티어)를 같은 클러스터, 같은 프롬프트, 콜드 스타트 조건에서 반복 실행했습니다.

| | Claude | Gemini | Codex |
|---|---|---|---|
| **Flagship** | Opus 4.7 | Gemini 2.5 Pro | GPT-5.5 |
| **Efficient** | Sonnet 4.6 ⭐ | Gemini 2.5 Flash | GPT-5.4 |
| **Lite** | Haiku 4.5 | Gemini 2.5 Flash-Lite | GPT-5.4-mini |

- **10개 시나리오** — CrashLoopBackOff, OOM, PVC, HPA, 카오스 등
- **점수 공식** — `Ops_Score = Quality × Safety × (0.55 + 0.45 × Efficiency)`
- **최고 성능** — Claude Sonnet 4.6이 전 티어 최고 Ops_Score 달성 (0.733)
- **테스트 클러스터** — Kubernetes 1.35.4, Vagrant + VirtualBox (컨트롤 플레인 1대, 워커 3대)

→ [블로그 포스트](https://kuberneteslab.dev/ko/blog/aiops-agent-benchmark/) · [README (EN)](./AIOps-Agent-Benchmark/README.md) · [README (KO)](./AIOps-Agent-Benchmark/README_ko.md) · [방법론](./AIOps-Agent-Benchmark/GUIDANCE.md)

---

### [gateway-PoC](./gateway-PoC)

7개 Kubernetes Gateway API 구현체를 라우팅, TLS, 트래픽 관리, 고급 기능 등 17개 항목으로 100 라운드 반복 검증한 PoC입니다.

| 등급 | 구현체 |
|---|---|
| **A (100%)** | NGINX Gateway Fabric · Envoy Gateway · Istio · Cilium |
| **F** | Kong · Traefik (Gateway API 호환성 미성숙) |
| **Skip** | kgateway (테스트 시점 ARM64 미지원) |

- **17개 테스트** — host/path/header 라우팅, TLS, 카나리, 레이트 리미팅, gRPC 등
- **핵심 발견** — 선언적 네이티브 레이트 리미팅(BackendTrafficPolicy)은 Envoy Gateway만 지원
- **테스트 환경** — Kubernetes 1.34.2, Apple Silicon(ARM64), Cilium CNI

→ [블로그 포스트](https://kuberneteslab.dev/ko/blog/gateway-api-comparison/) · [README (EN)](./gateway-PoC/README.md) · [README (KO)](./gateway-PoC/README_ko.md)

---

## 작성자

**조훈 (Hoon Jo)** · CNCF Ambassador · Kubestronaut · [@sysnet4admin](https://github.com/sysnet4admin) · [kuberneteslab.dev](https://kuberneteslab.dev/ko/)
