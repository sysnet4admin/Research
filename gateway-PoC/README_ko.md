# Kubernetes Gateway API PoC

[English](README.md)

Ingress에서 Gateway API로 마이그레이션을 위한 Gateway 구현체 비교 PoC (Proof of Concept)

## 1. 쿠버네티스 인프라 환경

### 클러스터 개요

| 항목 | 내용 |
|------|------|
| **Kubernetes 버전** | v1.34.2 |
| **아키텍처** | ARM64 (Apple Silicon) |
| **OS** | Ubuntu 22.04.5 LTS |
| **커널** | 5.15.0-142-generic |
| **컨테이너 런타임** | containerd 1.7.24 |
| **Gateway API 버전** | v1.2.0 |
| **네트워크 대역** | 192.168.1.0/24 |

### 노드 구성

#### Control Plane

| 항목 | 내용 |
|------|------|
| **노드명** | cp-k8s |
| **역할** | control-plane |
| **IP 주소** | 192.168.1.10 |
| **CPU** | 4 vCPU |
| **메모리** | 3.8 GB |
| **OS** | Ubuntu 22.04.5 LTS (ARM64) |

#### Worker Nodes

| 노드명 | 역할 | IP 주소 | CPU | 메모리 |
|--------|------|---------|-----|--------|
| w1-k8s | worker | 192.168.1.101 | 4 vCPU | 7.8 GB |
| w2-k8s | worker | 192.168.1.102 | 4 vCPU | 7.8 GB |
| w3-k8s | worker | 192.168.1.103 | 4 vCPU | 7.8 GB |

**총 클러스터 리소스**: 16 vCPU, 27.2 GB 메모리

### CNI 구성 (Cilium)

| 항목 | 내용 |
|------|------|
| **CNI** | Cilium |
| **버전** | v1.18.4 |
| **eBPF** | 활성화 |
| **kube-proxy 대체** | true (eBPF 기반) |
| **터널 모드** | VXLAN |
| **IPAM 모드** | cluster-pool |
| **Pod CIDR** | 10.0.0.0/8 |
| **L7 Proxy** | 활성화 |
| **Gateway API** | 활성화 (enable-gateway-api: true) |

#### Cilium 주요 설정

```yaml
# Gateway API 관련 설정
enable-gateway-api: "true"
enable-gateway-api-secrets-sync: "true"
enable-gateway-api-proxy-protocol: "true"

# eBPF 관련 설정
kube-proxy-replacement: "true"
enable-l7-proxy: "true"
tunnel-protocol: vxlan

# IPAM 설정
ipam: cluster-pool
cluster-pool-ipv4-cidr: 10.0.0.0/8
cluster-pool-ipv4-mask-size: "24"
```

### 설치된 GatewayClass

| GatewayClass | Controller | 상태 |
|--------------|------------|------|
| cilium | io.cilium/gateway-controller | Accepted |
| eg | gateway.envoyproxy.io/gatewayclass-controller | Accepted |
| istio | istio.io/gateway-controller | Accepted |
| kong | konghq.com/kic-gateway-controller | Accepted |
| nginx | gateway.nginx.org/nginx-gateway-controller | Accepted |
| traefik | traefik.io/gateway-controller | Accepted |
| kgateway | kgateway.io/kgateway | Waiting (ARM64 미지원) |

### Gateway 별 IP 할당

| Gateway | GatewayClass | IP Address | Namespace |
|---------|--------------|------------|-----------|
| NGINX Gateway Fabric | nginx | 192.168.1.11 | nginx-gateway |
| Envoy Gateway | envoy | 192.168.1.12 | envoy-gateway-system |
| kgateway | kgateway | 192.168.1.13 | kgateway-system |
| Istio Gateway | istio | 192.168.1.14 | istio-system |
| Cilium Gateway | cilium | 192.168.1.15 | kube-system |
| Kong Gateway | kong | 192.168.1.16 | kong |
| Traefik Gateway | traefik | 192.168.1.17 | traefik |

### 클러스터 아키텍처

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

### PoC 환경 특이사항

1. **ARM64 아키텍처**: Apple Silicon (M-series) 기반으로 AMD64 전용 이미지를 사용하는 kgateway는 테스트 불가
2. **멀티 Gateway**: 동일 클러스터에서 7개의 서로 다른 Gateway 구현체를 독립적으로 운영
3. **CNI 선택**: Cilium Gateway 테스트를 위해 Cilium CNI를 사용하였으며, CNI는 환경에 맞게 선택 가능

#### Cilium 외 다른 CNI 사용 시 고려사항

| 항목 | 영향 |
|------|------|
| **Cilium Gateway** | 사용 불가 (Cilium CNI 전용) |
| **테스트 대상** | 6개 Gateway (Cilium 제외) |
| **기타 Gateway** | 영향 없음 (NGINX, Envoy, Istio, Kong, Traefik, kgateway) |

---

## 2. Gateway 후보 선정 이유

### 2.1 NGINX Gateway Fabric

| 항목 | 내용 |
|------|------|
| **선정 이유** | 가장 널리 사용되는 웹 서버/리버스 프록시의 공식 Gateway API 구현체 |
| **장점** | 검증된 안정성, 풍부한 문서, 대규모 커뮤니티 지원 |
| **특징** | NGINX의 고성능 처리 능력을 Gateway API와 결합 |
| **공식 지원** | F5 Networks (NGINX Inc.) 공식 지원 |
| **테스트 버전** | v2.2.1 (2025-11-18 공개) |

### 2.2 Envoy Gateway

| 항목 | 내용 |
|------|------|
| **선정 이유** | CNCF Graduated 프로젝트인 Envoy Proxy 기반의 Gateway API 구현체 |
| **장점** | 뛰어난 확장성, Rate Limiting 네이티브 지원, 관측성 |
| **특징** | xDS 프로토콜 기반 동적 설정, 풍부한 필터 체인 |
| **공식 지원** | Envoy Gateway 프로젝트 (CNCF) |
| **테스트 버전** | v1.6.0 (2025-11-11 공개) |

### 2.3 Istio Gateway

| 항목 | 내용 |
|------|------|
| **선정 이유** | 서비스 메시의 사실상 표준인 Istio의 Gateway API 지원 |
| **장점** | mTLS 자동화, 트래픽 관리, 서비스 메시 통합 |
| **특징** | Envoy 기반이지만 Istio 컨트롤 플레인과 통합 |
| **공식 지원** | Istio 프로젝트 (CNCF) |
| **테스트 버전** | v1.28.0 (2025-11-05 공개) |

### 2.4 Cilium Gateway

| 항목 | 내용 |
|------|------|
| **선정 이유** | eBPF 기반 고성능 네트워킹의 Gateway API 구현체 |
| **장점** | 커널 레벨 처리로 높은 성능, 네트워크 정책 통합 |
| **특징** | eBPF를 활용한 효율적인 패킷 처리, L3/L4/L7 통합 |
| **공식 지원** | Isovalent / Cilium 프로젝트 (CNCF) |
| **테스트 버전** | v1.18.4 (2025-11-12 공개) |

### 2.5 Kong Gateway

| 항목 | 내용 |
|------|------|
| **선정 이유** | 엔터프라이즈 API Gateway 시장의 선두 주자 |
| **장점** | 풍부한 플러그인 생태계, 엔터프라이즈 지원 |
| **특징** | API 관리, 인증/인가, 트래픽 제어 기능 내장 |
| **공식 지원** | Kong Inc. |
| **테스트 버전** | v3.9 (Ingress Controller v3.5, 2025-07-17 공개) |
| **버전 제약** | KIC v3.5.3은 Kong Gateway v3.9와 호환성 문제로 설정 동기화 실패. v3.5 유지 권장 |

### 2.6 Traefik Gateway

| 항목 | 내용 |
|------|------|
| **선정 이유** | 클라우드 네이티브 환경에 특화된 리버스 프록시 |
| **장점** | 자동 서비스 디스커버리, Let's Encrypt 통합 |
| **특징** | 설정 간소화, 다양한 백엔드 지원 |
| **공식 지원** | Traefik Labs |
| **테스트 버전** | v3.6.2 (Helm Chart v37.4.0, 2025-11-18 공개) |

### 2.7 kgateway (Solo.io)

| 항목 | 내용 |
|------|------|
| **선정 이유** | Envoy 기반의 Kubernetes 네이티브 API Gateway |
| **장점** | GraphQL 지원, Envoy 필터 확장성 |
| **특징** | Solo.io의 Gloo Edge 기술 기반 |
| **제약** | ARM64 아키텍처 미지원 (AMD64 전용) |
| **테스트 버전** | v2.1.1 (2025-11-18 공개, 테스트 미수행 - ARM64 미지원) |

---

## 3. PoC 테스트 항목 (17개)

### 3.1 라우팅 테스트

| # | 테스트 항목 | 설명 |
|---|------------|------|
| 1 | **host-routing** | 호스트 헤더 기반 라우팅. `app.example.com`과 `api.example.com`을 다른 백엔드로 분기 |
| 2 | **path-routing** | URL 경로 기반 라우팅. `/api/*`, `/web/*` 등 경로 패턴에 따른 백엔드 분기 |
| 3 | **header-routing** | HTTP 헤더 값 기반 라우팅. `X-Version: v2` 헤더 존재 시 특정 백엔드로 라우팅 |

### 3.2 TLS/보안 테스트

| # | 테스트 항목 | 설명 |
|---|------------|------|
| 4 | **tls-termination** | Gateway에서 TLS 종료. HTTPS 요청을 수신하고 백엔드로 HTTP 전달 |
| 5 | **https-redirect** | HTTP → HTTPS 자동 리다이렉션. 80 포트 요청을 443으로 강제 전환 |
| 6 | **backend-tls** | Gateway와 백엔드 간 mTLS 통신. 내부 트래픽도 암호화 (사이드카 필요) |

### 3.3 트래픽 관리 테스트

| # | 테스트 항목 | 설명 |
|---|------------|------|
| 7 | **canary-traffic** | 카나리 배포를 위한 가중치 기반 트래픽 분배 (80% v1, 20% v2) |
| 8 | **rate-limiting** | 요청 속도 제한. 초당/분당 최대 요청 수 제한으로 서비스 보호 |
| 9 | **timeout-retry** | 요청 타임아웃 및 실패 시 자동 재시도 정책 설정 |
| 10 | **session-affinity** | 세션 기반 스티키 라우팅. 동일 클라이언트를 같은 백엔드로 유지 |

### 3.4 요청/응답 수정 테스트

| # | 테스트 항목 | 설명 |
|---|------------|------|
| 11 | **url-rewrite** | URL 경로 재작성. `/old-api/*` → `/new-api/*` 변환 |
| 12 | **header-modifier** | 요청/응답 헤더 추가, 수정, 삭제 기능 |

### 3.5 고급 기능 테스트

| # | 테스트 항목 | 설명 |
|---|------------|------|
| 13 | **cross-namespace** | 네임스페이스 간 라우팅. `gateway-poc` → `backend-ns`로의 크로스 네임스페이스 통신 |
| 14 | **grpc-routing** | gRPC 프로토콜 라우팅 지원. HTTP/2 기반 gRPC 트래픽 처리 |
| 15 | **health-check** | 백엔드 헬스 체크 및 자동 장애 감지 |

### 3.6 성능/안정성 테스트

| # | 테스트 항목 | 설명 |
|---|------------|------|
| 16 | **load-test** | 동시 요청 부하 테스트. 20개 동시 요청 처리 능력 측정 |
| 17 | **failover-recovery** | 장애 복구 테스트. Gateway Pod 재시작 후 정상화 확인 |

---

## 4. PoC 결과 (100 라운드 테스트)

### 4.1 Gateway별 성공률 요약

> **참고**: 성공률은 SKIP을 제외한 `PASS / (PASS + FAIL)` 기준으로 계산

| Gateway | 성공률 | PASS | FAIL | SKIP | 등급 |
|---------|--------|------|------|------|------|
| **NGINX Gateway Fabric** | 100% | 15 | 0 | 2 | A |
| **Envoy Gateway** | 100% | 15 | 0 | 2 | A |
| **Istio Gateway** | 100% | 15 | 0 | 2 | A |
| **Cilium Gateway** | 100% | 14 | 0 | 3 | A |
| **Kong Gateway** | 16.7% | 2 | 10 | 5 | F |
| **Traefik Gateway** | 8.3% | 1 | 11 | 5 | F |
| **kgateway** | N/A | 0 | 0 | 17 | Skip |

### 4.2 테스트 항목별 상세 결과

| # | 테스트 항목 | nginx | envoy | istio | cilium | kong | traefik | 비고 |
|---|------------|:-----:|:-----:|:-----:|:------:|:----:|:-------:|------|
| 1 | host-routing | PASS | PASS | PASS | PASS | FAIL | FAIL | |
| 2 | path-routing | PASS | PASS | PASS | PASS | FAIL | FAIL | |
| 3 | header-routing | PASS | PASS | PASS | PASS | FAIL | FAIL | |
| 4 | tls-termination | PASS | PASS | PASS | PASS | SKIP | SKIP | |
| 5 | https-redirect | PASS | PASS | PASS | PASS | SKIP | SKIP | |
| 6 | backend-tls | SKIP | SKIP | SKIP | SKIP | SKIP | SKIP | mTLS 미구성 (전체 미지원) |
| 7 | canary-traffic | PASS | PASS | PASS | PASS | FAIL | FAIL | |
| 8 | rate-limiting | PASS | PASS | PASS | SKIP | FAIL | FAIL | Envoy: 네이티브 CRD, NGINX/Istio: 로우레벨 설정, Cilium: 미지원 |
| 9 | timeout-retry | PASS | PASS | PASS | PASS | FAIL | FAIL | |
| 10 | session-affinity | SKIP | SKIP | SKIP | SKIP | SKIP | SKIP | 전체 미구성 |
| 11 | url-rewrite | PASS | PASS | PASS | PASS | FAIL | FAIL | |
| 12 | header-modifier | PASS | PASS | PASS | PASS | FAIL | FAIL | |
| 13 | cross-namespace | PASS | PASS | PASS | PASS | FAIL | FAIL | |
| 14 | grpc-routing | PASS | PASS | PASS | PASS | PASS | PASS | |
| 15 | health-check | PASS | PASS | PASS | PASS | SKIP | SKIP | |
| 16 | load-test | PASS | PASS | PASS | PASS | FAIL | FAIL | |
| 17 | failover-recovery | PASS | PASS | PASS | PASS | PASS | FAIL | |

**범례**:
- **PASS** = 성공
- **FAIL** = 실패
- **SKIP** = 정책 미구성 (지원하지만 테스트 환경에서 구성하지 않음)

### 4.3 Skip 사유 정리

| 테스트 항목 | Skip 사유 | 영향 Gateway |
|------------|----------|--------------|
| backend-tls | 사이드카 인젝션 미구성 (mTLS) | 전체 |
| session-affinity | 정책 미설정 | 전체 |
| tls-termination | Gateway Pod IP 미확보 | kong, traefik |
| https-redirect | 미구성 | kong, traefik |
| health-check | 미구성 | kong, traefik |
| rate-limiting | HTTP Rate Limiting 미지원 | cilium |
| kgateway 전체 | ARM64 아키텍처 미지원 | kgateway |

> **참고**: Rate Limiting 지원 현황은 2025년 12월 테스트 기준이며, Gateway 구현체들은 지속적으로 발전하고 있으므로 최신 문서를 확인하시기 바랍니다.

### 4.4 실패 원인 분석

#### Kong Gateway

```
오류: "no Route matched with those values"
```

- HTTPRoute 리소스가 Kong 내부로 동기화되지 않음
- "unmanaged gateway" 모드에서 Gateway API 호환성 문제
- 기본 라우팅 기능부터 동작하지 않아 대부분의 테스트 실패

#### Traefik Gateway

```
오류: "404 page not found"
경고: "Gateway not ready"
```

- EntryPoints 포트 불일치 (내부: 8000/8443, 외부: 80/443)
- BackendTLSPolicy CRD 버전 불일치 (v1alpha3 vs v1)
- Gateway가 Ready 상태에 도달하지 못해 라우팅 불가

---

## 5. 종합 의견

### 5.1 프로덕션 권장 Gateway

#### Tier 1: 강력 추천 (100% 성공률)

| 순위 | Gateway | 추천 이유 |
|------|---------|----------|
| 1 | **NGINX Gateway Fabric** | 검증된 안정성, 풍부한 문서, 대규모 트래픽 처리 경험 |
| 2 | **Envoy Gateway** | Gateway API 표준 준수, Rate Limiting 네이티브 지원, 우수한 확장성 |
| 3 | **Istio Gateway** | 서비스 메시 환경에 최적, mTLS 자동화, 트래픽 관리 통합 |
| 4 | **Cilium Gateway** | eBPF 기반 고성능, 네트워크 정책 통합, 클라우드 네이티브 |

### 5.2 Rate Limiting 지원 현황

> **참고**: Gateway API 표준에는 Rate Limiting 스펙이 아직 포함되어 있지 않으며, 구현체별로 지원 방식이 다릅니다. 2025년 12월 기준입니다.

| Gateway | Rate Limiting 지원 | 방식 | 비고 |
|---------|:------------------:|------|------|
| **Envoy Gateway** | **O (네이티브)** | [`BackendTrafficPolicy`](https://gateway.envoyproxy.io/docs/tasks/traffic/backend-traffic-policy/rate-limit/) | Gateway API 스타일 선언적 설정 |
| NGINX Gateway Fabric | △ (제한적) | [`SnippetsFilter`](https://docs.nginx.com/nginx-gateway-fabric/traffic-management/snippets/) | 로우레벨 NGINX 설정 필요 |
| Istio Gateway | △ (제한적) | [`EnvoyFilter`](https://istio.io/latest/docs/tasks/policy-enforcement/rate-limit/) | 로우레벨 Envoy 설정 필요 |
| Cilium Gateway | X (미지원) | - | [Feature Request #33500](https://github.com/cilium/cilium/issues/33500) |

**결론**: **Envoy Gateway만이** 선언적 CRD를 통한 네이티브 Rate Limiting을 지원합니다. NGINX(SnippetsFilter)와 Istio(EnvoyFilter)는 CRD를 통해 구성 가능하지만, 이는 로우레벨 설정 주입 방식으로 전용 Rate Limiting API가 아니어서 복잡도가 높습니다. Cilium은 현재 HTTP Rate Limiting을 지원하지 않습니다.

### 5.3 사용 사례별 추천

| 사용 사례 | 추천 Gateway | 이유 |
|----------|-------------|------|
| **범용 프로덕션** | NGINX Gateway Fabric | 안정성, 성숙도, 운영 경험 |
| **API Rate Limiting 필수** | Envoy Gateway | 선언적 Rate Limiting CRD를 네이티브 지원하는 유일한 Gateway |
| **서비스 메시 환경** | Istio Gateway | Istio 컨트롤 플레인과 완벽 통합 |
| **고성능/대용량 트래픽** | Cilium Gateway | eBPF 기반 커널 레벨 처리 |
| **멀티클라우드/하이브리드** | Envoy Gateway | xDS 프로토콜 기반 유연한 설정 |

### 5.4 마이그레이션 고려사항

#### 권장 사항

1. **점진적 마이그레이션**: 기존 Ingress와 Gateway API 병행 운영 후 순차 전환
2. **테스트 환경 우선**: 스테이징 환경에서 충분한 검증 후 프로덕션 적용
3. **모니터링 강화**: 마이그레이션 기간 동안 트래픽 및 오류율 모니터링 필수
4. **롤백 계획**: 문제 발생 시 즉시 Ingress로 롤백할 수 있는 플랜 준비

#### 주의 사항

1. **Kong/Traefik**: 본 PoC 환경에서 Gateway API 호환성 이슈가 발견되어 추가 구성 검토가 필요합니다. 두 제품 모두 우수한 API Gateway로 검증된 솔루션이지만, Gateway API 지원은 아직 성숙 단계에 있으므로 도입 전 최신 버전에서의 호환성 확인을 권장합니다.
2. **kgateway**: ARM64 환경에서는 사용 불가, AMD64 환경에서 재검토 필요
3. **backend-tls**: mTLS가 필요한 경우 서비스 메시(Istio) 도입 검토

### 5.5 결론

100회 반복 테스트 결과, **NGINX, Envoy, Istio, Cilium** 4개 Gateway가 **100% 일관된 결과**를 보여주며 프로덕션 환경에 안정적으로 적합합니다.

Rate Limiting의 경우, **Envoy Gateway만이 선언적 CRD를 통한 네이티브 지원**을 제공합니다(BackendTrafficPolicy). NGINX(SnippetsFilter)와 Istio(EnvoyFilter)는 로우레벨 설정 주입을 통해 구현 가능하지만 복잡도가 높습니다. Cilium은 현재 HTTP Rate Limiting을 지원하지 않습니다. API 트래픽 제어가 필요한 환경에는 **Envoy Gateway**가 가장 적합한 선택입니다.

**NGINX Gateway Fabric**은 가장 검증된 선택지로, 운영 안정성이 최우선인 환경에 적합합니다.

**Kong과 Traefik**은 각각의 Ingress Controller로서는 충분히 검증된 솔루션이나, Gateway API 지원은 현재 발전 중인 단계입니다. Gateway API 기반 마이그레이션을 고려할 경우, 최신 버전에서의 호환성 테스트와 추가 구성 검토를 권장합니다.

---

## 부록

### A. 테스트 실행 방법

```bash
# 17개 PoC 테스트 실행 (단일 라운드)
./run-gateway-poc-17tests.sh <round_number>

# 예: Round 1 테스트
./run-gateway-poc-17tests.sh 1
```

### B. 테스트 스크립트 주요 특징

- **구현체별 CRD 자동 감지**: Rate Limiting 테스트 시 각 Gateway의 CRD를 자동 감지하여 적용
- **타이밍 측정**: 각 테스트 항목별 실행 시간 측정
- **JSON 결과 출력**: 각 라운드 결과를 JSON 형식으로 저장 (`results/rounds/round-N.json`)

### C. 참고 자료

- [Kubernetes Gateway API 공식 문서](https://gateway-api.sigs.k8s.io/)
- [NGINX Gateway Fabric](https://github.com/nginxinc/nginx-gateway-fabric)
- [Envoy Gateway](https://gateway.envoyproxy.io/)
- [Istio Gateway API](https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/)
- [Cilium Gateway API](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/)
- [Kong Gateway Operator](https://docs.konghq.com/gateway-operator/latest/)
- [Traefik Kubernetes Gateway](https://doc.traefik.io/traefik/routing/providers/kubernetes-gateway/)
- [kgateway (Solo.io)](https://kgateway.io/)

---

**테스트 일시**: 2025-12-05
