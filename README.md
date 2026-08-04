# Research

[한국어](README_ko.md)

Benchmarks and proof-of-concept studies on Kubernetes, Cloud Native, and AI, the research backing for [kuberneteslab.dev](https://kuberneteslab.dev/en/).

---

## About

**[KubernetesLab](https://kuberneteslab.dev/en/)** is a research, consulting, and education platform focused on Kubernetes, Cloud Native, and AI. Each project in this repository is a hands-on study published as a blog post on the site. The research covers three areas:

- **AI / AIOps**: benchmarking AI coding agents on real Kubernetes operations and incident-response tasks
- **Kubernetes**: Gateway API implementations, cluster optimization, observability
- **FinOps**: cost reduction studies on EKS and AKS (49% and 48% savings)

---

## Projects

### [AIOps-Agent-Benchmark](./AIOps-Agent-Benchmark)

Compares nine AI coding agents (Claude, Gemini, Codex) on identical Kubernetes incident-response scenarios, measuring quality, safety, and efficiency.

→ [Blog post](https://kuberneteslab.dev/en/blog/aiops-agent-benchmark/) | [README (EN)](./AIOps-Agent-Benchmark/README.md) | [README (KO)](./AIOps-Agent-Benchmark/README_ko.md) | [Methodology](./AIOps-Agent-Benchmark/GUIDANCE.md)

---

### [gateway-PoC](./gateway-PoC)

Validates seven Kubernetes Gateway API implementations across 17 test cases (routing, TLS, traffic management) with 100 rounds each.

→ [Blog post](https://kuberneteslab.dev/en/blog/gateway-api-comparison/) | [README (EN)](./gateway-PoC/README.md) | [README (KO)](./gateway-PoC/README_ko.md)

---

### [agents-md-migration](./agents-md-migration)

Measures whether moving a project context file from CLAUDE.md to AGENTS.md (via import or symlink) slows Claude Code down or costs more tokens, across 5 model configurations on Kubernetes incident-response tasks. Result: no penalty on either axis.

→ [Blog post](https://kuberneteslab.dev/en/blog/agents-md-migration/) | [README (EN)](./agents-md-migration/README.md) | [README (KO)](./agents-md-migration/README_ko.md)

---

### [cni-benchmark](./cni-benchmark)

Measures the standing resource cost of five CNIs (Calico, Cilium, Flannel, Antrea, kube-router) across 14 configurations and 6 load phases: CPU, memory, and eBPF map kernel memory, over a 9-day unattended campaign. Key findings: memory (not CPU) separates the conditions, and switching kube-proxy to nftables mode alone cuts its memory usage by 70%.

→ [README (EN)](./cni-benchmark/README.md) | [README (KO)](./cni-benchmark/README_ko.md)

---

## Author

**Hoon Jo** / CNCF Ambassador / Kubestronaut / [@sysnet4admin](https://github.com/sysnet4admin) / [kuberneteslab.dev](https://kuberneteslab.dev/en/)
