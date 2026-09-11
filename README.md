# Research

[한국어](README_ko.md)

Benchmarks and proof-of-concept studies on Kubernetes, Cloud Native, and AI, the research backing for [kuberneteslab.dev](https://kuberneteslab.dev/en/).

---

## About

**[KubernetesLab](https://kuberneteslab.dev/en/)** is a research, consulting, and education platform focused on Kubernetes, Cloud Native, and AI. Each project in this repository is a hands-on study published as a blog post on the site. The research covers three areas:

- **AI / AIOps**: benchmarking AI coding agents, open-weight models, and agent harnesses on real Kubernetes operations and incident-response tasks
- **Agent protocols**: what MCP, A2A, and the gateways in front of them actually enforce, observe, and cost, measured rather than read off the spec
- **Kubernetes**: Gateway API implementations, CNI standing cost, cluster optimization, observability
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

→ [Blog post](https://kuberneteslab.dev/en/blog/cni-standing-cost/) | [README (EN)](./cni-benchmark/README.md) | [README (KO)](./cni-benchmark/README_ko.md)

---

### [mcp-migration](./mcp-migration)

Measures what the MCP 2026-07-28 stateless revision changes for a server running on Kubernetes. The same workload runs on a session-based server and on a port to the new spec, under scale-out, pod replacement, and three handle designs. Key findings: the old spec loses throughput as replicas are added (median 199.9 to 33.2 rps at four replicas, with 37,844 session losses out of 78,000 requests) and varies run to run, the new spec holds the offered rate in every condition measured, and a port that leaves handle state in pod memory reproduces the old failure behind HTTP 200.

→ [Blog post](https://kuberneteslab.dev/en/blog/mcp-stateless-migration/) | [README (EN)](./mcp-migration/README.md) | [README (KO)](./mcp-migration/README_ko.md)

---

### [mcp-server-benchmark](./mcp-server-benchmark)

Compares six Kubernetes MCP servers on one scale: the probe model, the ten incident scenarios, the harness, the cluster, and the scoring are held fixed and only the MCP server is swapped, over 240 runs. Key findings: plugging in an MCP server is not free quality, since four of the six score below the plain-shell baseline (0.9167), and every general-purpose server costs more tokens than shell because tool definitions ship into the context window. The top two are close enough that cost, not score, should decide.

→ [README (EN)](./mcp-server-benchmark/README.md) | [README (KO)](./mcp-server-benchmark/README_ko.md)

---

### [agentgateway-study](./agentgateway-study)

Measures whether agentgateway (v1.5.0 on Kubernetes 1.37; first round on v1.4.1) actually enforces and observes what its docs say when fronting MCP servers. Key findings: an authorization rule conditioned on tool arguments passes validation yet locks the whole backend (reported upstream as #3092), policies evaluate the original tool name rather than the renamed one, traceparent propagates in both the header and `_meta`, the gateway costs under 1 ms at p50 per tool call and does not lower the tail at any backend processing time, and allowlist filtering of `tools/list` is free at the gateway but saves no latency. The A2A surface (card rewriting, no A2A authorization) is a section of the same study.

→ [README (EN)](./agentgateway-study/README.md) | [README (KO)](./agentgateway-study/README_ko.md)

---

### [agentgateway-study/a2a](./agentgateway-study/a2a)

Measures what agentgateway (v1.5.0) actually enforces and observes when fronting an A2A agent. Key findings: agent card rewriting is opt-in and a mixed-format card (v0.3 `url` plus v1.0 `supportedInterfaces`, the official Python SDK's default) keeps advertising the direct backend address even with the switch on, so a v0.3 client bypasses the gateway; the A2A surface has no request-authorization policy (observation without enforcement); JSON-RPC errors ride HTTP 200 but land in the access log; the gateway hop costs +0.8 to 3.0 ms p50 depending on connection mode, with A2A protocol processing itself at +0.0 to 0.2 ms.

→ [README (EN)](./agentgateway-study/a2a/README.md) | [README (KO)](./agentgateway-study/a2a/README_ko.md)

---

### [a2a-study](./a2a-study)

Asks when and how A2A is actually useful, rather than what the spec says. Stage 1 measures three things: what the spec declares against what the official SDK does by default, how A2A compares with MCP and with plain HTTP for the same handoff, and what the protocol itself costs. Stage 2 will cover interoperability across the two generations and passing through a gateway. This is a separate study from the A2A surface of agentgateway above, which measures what a gateway enforces; this one measures the protocol.

→ [README (EN)](./a2a-study/README.md) | [README (KO)](./a2a-study/README_ko.md)

---

## Author

**Hoon Jo** / CNCF Ambassador / AAIF Ambassador / Kubestronaut / [@sysnet4admin](https://github.com/sysnet4admin) / [kuberneteslab.dev](https://kuberneteslab.dev/en/)
