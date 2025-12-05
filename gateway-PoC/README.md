# Kubernetes Gateway API PoC

[한국어](README_ko.md)

A Proof of Concept for comparing Gateway implementations for migration from Ingress to Gateway API.

## 1. Kubernetes Infrastructure Environment

### Cluster Overview

| Item | Details |
|------|---------|
| **Kubernetes Version** | v1.34.2 |
| **Architecture** | ARM64 (Apple Silicon) |
| **OS** | Ubuntu 22.04.5 LTS |
| **Kernel** | 5.15.0-142-generic |
| **Container Runtime** | containerd 1.7.24 |
| **Gateway API Version** | v1.2.0 |
| **Network Range** | 192.168.1.0/24 |

### Node Configuration

#### Control Plane

| Item | Details |
|------|---------|
| **Node Name** | cp-k8s |
| **Role** | control-plane |
| **IP Address** | 192.168.1.10 |
| **CPU** | 4 vCPU |
| **Memory** | 3.8 GB |
| **OS** | Ubuntu 22.04.5 LTS (ARM64) |

#### Worker Nodes

| Node Name | Role | IP Address | CPU | Memory |
|-----------|------|------------|-----|--------|
| w1-k8s | worker | 192.168.1.101 | 4 vCPU | 7.8 GB |
| w2-k8s | worker | 192.168.1.102 | 4 vCPU | 7.8 GB |
| w3-k8s | worker | 192.168.1.103 | 4 vCPU | 7.8 GB |

**Total Cluster Resources**: 16 vCPU, 27.2 GB Memory

### CNI Configuration (Cilium)

| Item | Details |
|------|---------|
| **CNI** | Cilium |
| **Version** | v1.18.4 |
| **eBPF** | Enabled |
| **kube-proxy Replacement** | true (eBPF-based) |
| **Tunnel Mode** | VXLAN |
| **IPAM Mode** | cluster-pool |
| **Pod CIDR** | 10.0.0.0/8 |
| **L7 Proxy** | Enabled |
| **Gateway API** | Enabled (enable-gateway-api: true) |

#### Key Cilium Settings

```yaml
# Gateway API related settings
enable-gateway-api: "true"
enable-gateway-api-secrets-sync: "true"
enable-gateway-api-proxy-protocol: "true"

# eBPF related settings
kube-proxy-replacement: "true"
enable-l7-proxy: "true"
tunnel-protocol: vxlan

# IPAM settings
ipam: cluster-pool
cluster-pool-ipv4-cidr: 10.0.0.0/8
cluster-pool-ipv4-mask-size: "24"
```

### Installed GatewayClasses

| GatewayClass | Controller | Status |
|--------------|------------|--------|
| cilium | io.cilium/gateway-controller | Accepted |
| eg | gateway.envoyproxy.io/gatewayclass-controller | Accepted |
| istio | istio.io/gateway-controller | Accepted |
| kong | konghq.com/kic-gateway-controller | Accepted |
| nginx | gateway.nginx.org/nginx-gateway-controller | Accepted |
| traefik | traefik.io/gateway-controller | Accepted |
| kgateway | kgateway.io/kgateway | Waiting (ARM64 not supported) |

### Gateway IP Assignments

| Gateway | GatewayClass | IP Address | Namespace |
|---------|--------------|------------|-----------|
| NGINX Gateway Fabric | nginx | 192.168.1.11 | nginx-gateway |
| Envoy Gateway | envoy | 192.168.1.12 | envoy-gateway-system |
| kgateway | kgateway | 192.168.1.13 | kgateway-system |
| Istio Gateway | istio | 192.168.1.14 | istio-system |
| Cilium Gateway | cilium | 192.168.1.15 | kube-system |
| Kong Gateway | kong | 192.168.1.16 | kong |
| Traefik Gateway | traefik | 192.168.1.17 | traefik |

### Cluster Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         Kubernetes Cluster (v1.34.2)                          │
│                                                                               │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                     Control Plane (cp-k8s)                               │ │
│  │                     192.168.1.10 | 4 CPU | 3.8GB                         │ │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐                    │ │
│  │  │ kube-api │ │ etcd     │ │scheduler │ │ctrl-mgr  │                    │ │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘                    │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                               │
│  ┌───────────────────┐ ┌───────────────────┐ ┌───────────────────┐          │
│  │ Worker: w1-k8s    │ │ Worker: w2-k8s    │ │ Worker: w3-k8s    │          │
│  │ 192.168.1.101     │ │ 192.168.1.102     │ │ 192.168.1.103     │          │
│  │ 4 CPU | 7.8GB     │ │ 4 CPU | 7.8GB     │ │ 4 CPU | 7.8GB     │          │
│  └───────────────────┘ └───────────────────┘ └───────────────────┘          │
│                                                                               │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                     CNI: Cilium v1.18.4 (eBPF)                           │ │
│  │  • kube-proxy replacement  • Gateway API enabled  • VXLAN tunnel        │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                               │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐            │
│  │   nginx     │ │   envoy     │ │   istio     │ │  cilium     │            │
│  │  Gateway    │ │  Gateway    │ │  Gateway    │ │  Gateway    │            │
│  │ 192.168.1.11│ │ 192.168.1.12│ │ 192.168.1.14│ │ 192.168.1.15│            │
│  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘            │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                            │
│  │    kong     │ │  traefik    │ │  kgateway   │                            │
│  │  Gateway    │ │  Gateway    │ │  (Skip)     │                            │
│  │ 192.168.1.16│ │ 192.168.1.17│ │ ARM64 N/A   │                            │
│  └─────────────┘ └─────────────┘ └─────────────┘                            │
│                                                                               │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                        Backend Services                                  │ │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────┐            │ │
│  │  │ echo-v1  │ │ echo-v2  │ │  grpc    │ │ backend-ns       │            │ │
│  │  │ (stable) │ │ (canary) │ │ (HTTP/2) │ │ (cross-namespace)│            │ │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────────────┘            │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────┘
```

### PoC Environment Notes

1. **ARM64 Architecture**: Based on Apple Silicon (M-series), kgateway which only supports AMD64 images cannot be tested
2. **Multi-Gateway**: 7 different Gateway implementations running independently in the same cluster
3. **CNI Selection**: Cilium CNI was used to test Cilium Gateway; CNI can be selected based on your environment

#### Considerations When Using CNI Other Than Cilium

| Item | Impact |
|------|--------|
| **Cilium Gateway** | Not available (Cilium CNI exclusive) |
| **Test Targets** | 6 Gateways (excluding Cilium) |
| **Other Gateways** | No impact (NGINX, Envoy, Istio, Kong, Traefik, kgateway) |

---

## 2. Gateway Candidate Selection Rationale

### 2.1 NGINX Gateway Fabric

| Item | Details |
|------|---------|
| **Selection Reason** | Official Gateway API implementation of the most widely used web server/reverse proxy |
| **Advantages** | Proven stability, extensive documentation, large community support |
| **Features** | Combines NGINX's high-performance processing with Gateway API |
| **Official Support** | F5 Networks (NGINX Inc.) official support |
| **Tested Version** | v2.2.1 (Released 2025-11-18) |

### 2.2 Envoy Gateway

| Item | Details |
|------|---------|
| **Selection Reason** | Gateway API implementation based on CNCF Graduated project Envoy Proxy |
| **Advantages** | Excellent extensibility, native Rate Limiting support, observability |
| **Features** | xDS protocol-based dynamic configuration, rich filter chain |
| **Official Support** | Envoy Gateway Project (CNCF) |
| **Tested Version** | v1.6.0 (Released 2025-11-11) |

### 2.3 Istio Gateway

| Item | Details |
|------|---------|
| **Selection Reason** | Gateway API support from Istio, the de facto standard for service mesh |
| **Advantages** | Automated mTLS, traffic management, service mesh integration |
| **Features** | Envoy-based but integrated with Istio control plane |
| **Official Support** | Istio Project (CNCF) |
| **Tested Version** | v1.28.0 (Released 2025-11-05) |

### 2.4 Cilium Gateway

| Item | Details |
|------|---------|
| **Selection Reason** | Gateway API implementation of eBPF-based high-performance networking |
| **Advantages** | High performance with kernel-level processing, network policy integration |
| **Features** | Efficient packet processing using eBPF, L3/L4/L7 integration |
| **Official Support** | Isovalent / Cilium Project (CNCF) |
| **Tested Version** | v1.18.4 (Released 2025-11-12) |

### 2.5 Kong Gateway

| Item | Details |
|------|---------|
| **Selection Reason** | Market leader in enterprise API Gateway |
| **Advantages** | Rich plugin ecosystem, enterprise support |
| **Features** | Built-in API management, authentication/authorization, traffic control |
| **Official Support** | Kong Inc. |
| **Tested Version** | v3.9 (Ingress Controller v3.5, Released 2025-07-17) |
| **Version Note** | KIC v3.5.3 has compatibility issues with Kong Gateway v3.9, causing config sync failures. Recommend staying on v3.5 |

### 2.6 Traefik Gateway

| Item | Details |
|------|---------|
| **Selection Reason** | Reverse proxy specialized for cloud-native environments |
| **Advantages** | Automatic service discovery, Let's Encrypt integration |
| **Features** | Simplified configuration, various backend support |
| **Official Support** | Traefik Labs |
| **Tested Version** | v3.6.2 (Helm Chart v37.4.0, Released 2025-11-18) |

### 2.7 kgateway (Solo.io)

| Item | Details |
|------|---------|
| **Selection Reason** | Kubernetes-native API Gateway based on Envoy |
| **Advantages** | GraphQL support, Envoy filter extensibility |
| **Features** | Based on Solo.io's Gloo Edge technology |
| **Limitation** | ARM64 architecture not supported (AMD64 only) |
| **Tested Version** | v2.1.1 (Released 2025-11-18, Not tested - ARM64 not supported) |

---

## 3. PoC Test Items (17 Tests)

### 3.1 Routing Tests

| # | Test Item | Description |
|---|-----------|-------------|
| 1 | **host-routing** | Host header-based routing. Route `app.example.com` and `api.example.com` to different backends |
| 2 | **path-routing** | URL path-based routing. Backend routing based on path patterns like `/api/*`, `/web/*` |
| 3 | **header-routing** | HTTP header value-based routing. Route to specific backend when `X-Version: v2` header exists |

### 3.2 TLS/Security Tests

| # | Test Item | Description |
|---|-----------|-------------|
| 4 | **tls-termination** | TLS termination at Gateway. Receive HTTPS requests and forward HTTP to backend |
| 5 | **https-redirect** | Automatic HTTP → HTTPS redirection. Force redirect port 80 requests to 443 |
| 6 | **backend-tls** | mTLS communication between Gateway and backend. Encrypt internal traffic (requires sidecar) |

### 3.3 Traffic Management Tests

| # | Test Item | Description |
|---|-----------|-------------|
| 7 | **canary-traffic** | Weight-based traffic distribution for canary deployment (80% v1, 20% v2) |
| 8 | **rate-limiting** | Request rate limiting. Protect services by limiting max requests per second/minute |
| 9 | **timeout-retry** | Request timeout and automatic retry policy configuration on failure |
| 10 | **session-affinity** | Session-based sticky routing. Maintain same client to same backend |

### 3.4 Request/Response Modification Tests

| # | Test Item | Description |
|---|-----------|-------------|
| 11 | **url-rewrite** | URL path rewriting. Transform `/old-api/*` → `/new-api/*` |
| 12 | **header-modifier** | Add, modify, delete request/response headers |

### 3.5 Advanced Feature Tests

| # | Test Item | Description |
|---|-----------|-------------|
| 13 | **cross-namespace** | Cross-namespace routing. Communication from `gateway-poc` → `backend-ns` |
| 14 | **grpc-routing** | gRPC protocol routing support. HTTP/2-based gRPC traffic handling |
| 15 | **health-check** | Backend health check and automatic failure detection |

### 3.6 Performance/Reliability Tests

| # | Test Item | Description |
|---|-----------|-------------|
| 16 | **load-test** | Concurrent request load test. Measure ability to handle 20 concurrent requests |
| 17 | **failover-recovery** | Failover recovery test. Verify normalization after Gateway Pod restart |

---

## 4. PoC Results (100 Round Tests)

### 4.1 Gateway Success Rate Summary

> **Note**: Success rate is calculated as `PASS / (PASS + FAIL)` excluding SKIP

| Gateway | Success Rate | PASS | FAIL | SKIP | Grade |
|---------|--------------|------|------|------|-------|
| **NGINX Gateway Fabric** | 100% | 15 | 0 | 2 | A |
| **Envoy Gateway** | 100% | 15 | 0 | 2 | A |
| **Istio Gateway** | 100% | 15 | 0 | 2 | A |
| **Cilium Gateway** | 100% | 15 | 0 | 2 | A |
| **Kong Gateway** | 16.7% | 2 | 10 | 5 | F |
| **Traefik Gateway** | 8.3% | 1 | 11 | 5 | F |
| **kgateway** | N/A | 0 | 0 | 17 | Skip |

### 4.2 Detailed Results by Test Item

| # | Test Item | nginx | envoy | istio | cilium | kong | traefik | Notes |
|---|-----------|:-----:|:-----:|:-----:|:------:|:----:|:-------:|-------|
| 1 | host-routing | PASS | PASS | PASS | PASS | FAIL | FAIL | |
| 2 | path-routing | PASS | PASS | PASS | PASS | FAIL | FAIL | |
| 3 | header-routing | PASS | PASS | PASS | PASS | FAIL | FAIL | |
| 4 | tls-termination | PASS | PASS | PASS | PASS | SKIP | SKIP | |
| 5 | https-redirect | PASS | PASS | PASS | PASS | SKIP | SKIP | |
| 6 | backend-tls | SKIP | SKIP | SKIP | SKIP | SKIP | SKIP | mTLS not configured (all unsupported) |
| 7 | canary-traffic | PASS | PASS | PASS | PASS | FAIL | FAIL | |
| 8 | rate-limiting | PASS | PASS | PASS | PASS | FAIL | FAIL | Auto-detection of implementation-specific CRDs |
| 9 | timeout-retry | PASS | PASS | PASS | PASS | FAIL | FAIL | |
| 10 | session-affinity | SKIP | SKIP | SKIP | SKIP | SKIP | SKIP | Not configured for all |
| 11 | url-rewrite | PASS | PASS | PASS | PASS | FAIL | FAIL | |
| 12 | header-modifier | PASS | PASS | PASS | PASS | FAIL | FAIL | |
| 13 | cross-namespace | PASS | PASS | PASS | PASS | FAIL | FAIL | |
| 14 | grpc-routing | PASS | PASS | PASS | PASS | PASS | PASS | |
| 15 | health-check | PASS | PASS | PASS | PASS | SKIP | SKIP | |
| 16 | load-test | PASS | PASS | PASS | PASS | FAIL | FAIL | |
| 17 | failover-recovery | PASS | PASS | PASS | PASS | PASS | FAIL | |

**Legend**:
- **PASS** = Success
- **FAIL** = Failure
- **SKIP** = Policy not configured (supported but not configured in test environment)

### 4.3 Skip Reasons Summary

| Test Item | Skip Reason | Affected Gateway |
|-----------|-------------|------------------|
| backend-tls | Sidecar injection not configured (mTLS) | All |
| session-affinity | Policy not set | All |
| tls-termination | Gateway Pod IP not obtained | kong, traefik |
| https-redirect | Not configured | kong, traefik |
| health-check | Not configured | kong, traefik |
| kgateway all tests | ARM64 architecture not supported | kgateway |

### 4.4 Failure Root Cause Analysis

#### Kong Gateway

```
Error: "no Route matched with those values"
```

- HTTPRoute resources not synchronized to Kong internal
- Gateway API compatibility issues in "unmanaged gateway" mode
- Most tests failed as basic routing functionality did not work

#### Traefik Gateway

```
Error: "404 page not found"
Warning: "Gateway not ready"
```

- EntryPoints port mismatch (internal: 8000/8443, external: 80/443)
- BackendTLSPolicy CRD version mismatch (v1alpha3 vs v1)
- Routing unavailable as Gateway failed to reach Ready state

---

## 5. Summary and Recommendations

### 5.1 Production-Recommended Gateways

#### Tier 1: Highly Recommended (100% Success Rate)

| Rank | Gateway | Recommendation Reason |
|------|---------|----------------------|
| 1 | **NGINX Gateway Fabric** | Proven stability, extensive documentation, large-scale traffic handling experience |
| 2 | **Envoy Gateway** | Gateway API standard compliance, native Rate Limiting support, excellent extensibility |
| 3 | **Istio Gateway** | Optimal for service mesh environments, automated mTLS, integrated traffic management |
| 4 | **Cilium Gateway** | eBPF-based high performance, network policy integration, cloud-native |

### 5.2 Rate Limiting Support Status

> **Note**: The Gateway API standard does not yet include Rate Limiting specification. Each implementation supports it through extension APIs.

| Gateway | Rate Limiting Support | Method | Notes |
|---------|:---------------------:|--------|-------|
| **Envoy Gateway** | O (Native) | BackendTrafficPolicy CRD | Gateway API style declarative configuration |
| **NGINX Gateway Fabric** | O (Native) | NginxProxy CRD | Implementation-specific CRD configuration |
| **Istio Gateway** | O (Native) | Telemetry CRD | Implementation-specific CRD configuration |
| **Cilium Gateway** | O (Native) | CiliumClusterwideNetworkPolicy | Implementation-specific CRD configuration |

**PoC Result**: Rate Limiting tests performed using **auto-detection of implementation-specific CRDs**. All 4 Gateways confirmed to support Rate Limiting through their respective implementation-specific methods.

### 5.3 Use Case Recommendations

| Use Case | Recommended Gateway | Reason |
|----------|---------------------|--------|
| **General Production** | NGINX Gateway Fabric | Stability, maturity, operational experience |
| **API Rate Limiting Required** | Envoy Gateway | Gateway API style native Rate Limiting support |
| **Service Mesh Environment** | Istio Gateway | Perfect integration with Istio control plane |
| **High Performance/Large Traffic** | Cilium Gateway | eBPF-based kernel-level processing |
| **Multi-cloud/Hybrid** | Envoy Gateway | Flexible configuration based on xDS protocol |

### 5.4 Migration Considerations

#### Recommendations

1. **Gradual Migration**: Operate existing Ingress and Gateway API in parallel, then transition sequentially
2. **Test Environment First**: Sufficient validation in staging environment before production deployment
3. **Enhanced Monitoring**: Traffic and error rate monitoring essential during migration period
4. **Rollback Plan**: Prepare a plan for immediate rollback to Ingress if issues occur

#### Cautions

1. **Kong/Traefik**: Gateway API compatibility issues were found in this PoC environment, requiring additional configuration review. Both products are proven solutions as excellent API Gateways, but Gateway API support is still maturing. Compatibility verification on the latest version is recommended before adoption.
2. **kgateway**: Not available in ARM64 environment, requires re-evaluation in AMD64 environment
3. **backend-tls**: Consider service mesh (Istio) adoption if mTLS is required

### 5.5 Conclusion

After 100 rounds of testing, **NGINX, Envoy, Istio, and Cilium** - 4 Gateways showed **100% consistent results** and are stably suitable for production environments.

All 4 Tier 1 Gateways **support Rate Limiting through implementation-specific CRDs**. **Envoy Gateway** particularly natively supports Gateway API style declarative Rate Limiting via BackendTrafficPolicy CRD, making it most suitable for environments requiring API traffic control.

**NGINX Gateway Fabric** is the most proven choice, suitable for environments where operational stability is the top priority.

**Kong and Traefik** are well-proven solutions as their respective Ingress Controllers, but Gateway API support is currently in development. When considering Gateway API-based migration, compatibility testing and additional configuration review on the latest version is recommended.

---

## Appendix

### A. Test Execution Method

```bash
# Run 17 PoC tests (single round)
./run-gateway-poc-17tests.sh <round_number>

# Example: Round 1 test
./run-gateway-poc-17tests.sh 1
```

### B. Test Script Key Features

- **Auto-detection of implementation-specific CRDs**: Automatically detects and applies each Gateway's CRD for Rate Limiting tests
- **Timing measurement**: Measures execution time for each test item
- **JSON result output**: Saves each round's results in JSON format (`results/rounds/round-N.json`)

### C. References

- [Kubernetes Gateway API Official Documentation](https://gateway-api.sigs.k8s.io/)
- [NGINX Gateway Fabric](https://github.com/nginxinc/nginx-gateway-fabric)
- [Envoy Gateway](https://gateway.envoyproxy.io/)
- [Istio Gateway API](https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/)
- [Cilium Gateway API](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/)
- [Kong Gateway Operator](https://docs.konghq.com/gateway-operator/latest/)
- [Traefik Kubernetes Gateway](https://doc.traefik.io/traefik/routing/providers/kubernetes-gateway/)
- [kgateway (Solo.io)](https://kgateway.io/)

---

**Test Date**: 2025-12-05
