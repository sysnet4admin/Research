# Research

[한국어](README_ko.md)

Benchmarks and proof-of-concept studies on Kubernetes, Cloud Native, and AI — the research backing for [kuberneteslab.dev](https://kuberneteslab.dev/en/).

---

## About

**[KubernetesLab](https://kuberneteslab.dev/en/)** is a research, consulting, and education platform focused on Kubernetes, Cloud Native, and AI. Each project in this repository is a hands-on study published as a blog post on the site. The research covers three areas:

- **AI / AIOps** — benchmarking AI coding agents on real Kubernetes operations and incident-response tasks
- **Kubernetes** — Gateway API implementations, cluster optimization, observability
- **FinOps** — cost reduction studies on EKS and AKS (49% and 48% savings)

---

## Projects

### [AIOps-Agent-Benchmark](./AIOps-Agent-Benchmark)

Measures the **quality, safety, and efficiency** of nine AI coding agents across identical Kubernetes operations and incident-response scenarios.

This is not a general coding benchmark — it is scoped to the **AIOps / SRE** context: deploy, rollback, incident diagnosis, and observability. Nine agents (3 brands × 3 model tiers) run against the same cluster, the same prompts, and a cold start.

| | Claude | Gemini | Codex |
|---|---|---|---|
| **Flagship** | Opus 4.7 | Gemini 2.5 Pro | GPT-5.5 |
| **Efficient** | Sonnet 4.6 ⭐ | Gemini 2.5 Flash | GPT-5.4 |
| **Lite** | Haiku 4.5 | Gemini 2.5 Flash-Lite | GPT-5.4-mini |

- **10 scenarios** — CrashLoopBackOff, OOM, PVC, HPA, chaos, and more
- **Scoring** — `Ops_Score = Quality × Safety × (0.55 + 0.45 × Efficiency)`
- **Top result** — Claude Sonnet 4.6 achieved the highest Ops_Score (0.733) across all tiers
- **Test cluster** — Kubernetes 1.35.4 on Vagrant + VirtualBox (1 control-plane, 3 workers)

→ [Blog post](https://kuberneteslab.dev/en/blog/aiops-agent-benchmark/) · [README (EN)](./AIOps-Agent-Benchmark/README.md) · [README (KO)](./AIOps-Agent-Benchmark/README_ko.md) · [Methodology](./AIOps-Agent-Benchmark/GUIDANCE.md)

---

### [gateway-PoC](./gateway-PoC)

Validates seven Kubernetes Gateway API implementations against 17 test cases across routing, TLS, traffic management, and advanced features — 100 rounds each.

| Grade | Implementations |
|---|---|
| **A (100%)** | NGINX Gateway Fabric · Envoy Gateway · Istio · Cilium |
| **F** | Kong · Traefik (Gateway API compatibility issues) |
| **Skip** | kgateway (no ARM64 support at time of test) |

- **17 test cases** — host/path/header routing, TLS, canary, rate-limiting, gRPC, and more
- **Key finding** — Only Envoy Gateway offers declarative native rate-limiting (BackendTrafficPolicy)
- **Environment** — Kubernetes 1.34.2 on Apple Silicon (ARM64), Cilium CNI

→ [Blog post](https://kuberneteslab.dev/en/blog/gateway-api-comparison/) · [README (EN)](./gateway-PoC/README.md) · [README (KO)](./gateway-PoC/README_ko.md)

---

## Author

**Hoon Jo** · CNCF Ambassador · Kubestronaut · [@sysnet4admin](https://github.com/sysnet4admin) · [kuberneteslab.dev](https://kuberneteslab.dev/en/)
