# 구현체 설치 (install 단계)

7개 Gateway API 구현체의 **컨트롤러**를 설치한다. Gateway/HTTPRoute/백엔드 등
테스트 픽스처는 여기서 만들지 않는다(측정 단계에서 배포). 즉 이 단계의 산출물은
"7개 GatewayClass가 준비된 클러스터"이고, 설치 완료 후 스냅샷을 찍어 측정 라운드의
baseline으로 삼는다.

## 핵심 원칙: v1.4 호환 버전으로 핀

target은 Gateway API **v1.4**(SCORING.md 9장). 다수 구현체의 **최신 버전은
v1.5용**이라 v1.4 CRD와 충돌한다. 따라서 최신이 아니라 **v1.4 호환 버전**으로 핀한다.
패치 번호는 매월 바뀌므로 설치 직전 확인하되, MINOR는 v1.4 정합으로 고정한다.

| 구현체 | 핀 버전(v1.4 호환) | 최신(참고, v1.5용) | 설치 |
|---|---|---|---|
| NGINX Gateway Fabric | **2.4.2** (GW API 1.4.1) | 2.6.x | helm OCI |
| Envoy Gateway | **v1.7.x** (1.4.1) | v1.8 | helm OCI `--skip-crds` |
| Istio | **1.30.x** (1.28+ = v1.4) | - | helm base+istiod |
| Cilium | **1.19.4** (CNI 고정, v1.4.1) | - | helm upgrade `--reuse-values` |
| Traefik | **v3.6.x** (v1.4) | v3.7 | helm, image.tag 핀 |
| kgateway | **2.2.2** (GW API 1.2-1.4, arm64 2.2+) | 2.3.x | helm OCI, CRD 차트 skip |
| Kong (KGO managed) | **2.1.x** (image.tag 2.1, v1.4 지원) | - | helm, GatewayConfiguration |

> Kong 주의: 2.0.x는 v1.4 미지원, **2.1.x부터 v1.4 지원**. 신규 KGO managed
> gateway 경로(legacy KIC 아님).

## GatewayClass / controllerName / 네임스페이스 (substrate 계약)

| 구현체 | GatewayClass | controllerName | 컨트롤러 ns |
|---|---|---|---|
| nginx | `nginx` | `gateway.nginx.org/nginx-gateway-controller` | nginx-gateway |
| envoy | `eg` | `gateway.envoyproxy.io/gatewayclass-controller` | envoy-gateway-system |
| istio | `istio` (auto) | `istio.io/gateway-controller` | istio-system |
| cilium | `cilium` (auto) | `io.cilium/gateway-controller` | kube-system |
| kong | `kong` | `konghq.com/gateway-operator` | kong-system |
| traefik | `traefik` | `traefik.io/gateway-controller` | traefik |
| kgateway | `kgateway` (auto) | `kgateway.dev/kgateway` | kgateway-system |

## CRD 처리

Gateway API v1.4.1 **experimental 채널** CRD를 `00-gateway-api-crds.sh`로 먼저
설치한다(공용 단일 소스). 각 구현체는 자체 CRD를 다시 깔지 않도록 한다:
- Envoy Gateway: `--skip-crds`
- kgateway: `kgateway-crds` 차트와 `standard-install.yaml` 생략
- 나머지: CRD 선행단계만 건너뜀(차트가 Gateway API CRD를 안 깖)

## LB IP

대부분 Gateway 생성 시 LoadBalancer Service를 자동 생성 → MetalLB(.11-17 풀)가 IP 부여.
**예외: Traefik**은 차트가 Traefik 프록시용 LB Service 1개를 만들고 Gateway가 그
entryPoint를 공유한다(Gateway별 Service 아님). Gateway listener 포트가 Traefik
entryPoint(web/websecure)와 일치해야 한다.

IP는 **측정 단계에서 동적으로 읽는다**(`gateway.status.addresses` 또는 Service).
하드코딩하지 않는다(기존 결함 수정).

## 실행

```bash
export KUBE_CONTEXT=gateway-PoC
./install-all.sh                 # 00-crds → 7개 컨트롤러 순차 설치
# 완료 후 test-cluster/snapshot.sh 로 baseline 스냅샷
```

개별 재설치: `./<impl>/install.sh`
