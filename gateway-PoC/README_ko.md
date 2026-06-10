# Kubernetes Gateway API PoC

[English](README.md)

Ingress(ingress-nginx)에서 Kubernetes Gateway API로 옮기는 팀을 위한, 7개 구현체 라이브 클러스터 벤치마크.

## 이 벤치마크를 읽는 두 가지 방법

같은 측정(라이브 클러스터 7개 구현체, Gateway API v1.4)을 두 렌즈로 제시한다. 질문에 맞는 쪽을 고르면 된다.

| 뷰 | 당신의 질문 | 위치 |
|---|---|---|
| **출발점 (마이그레이션)** | "ingress-nginx를 쓰는데, 각 구현체로 옮기면 뭐가 넘어가고 뭐가 막히나?" | [`metrics/migration-view/`](metrics/migration-view/) |
| **엄밀성 (conformance)** | "각 구현체가 Gateway API 스펙을 얼마나 엄밀히 구현했고, 측정상 얼마나 잘 동작하나?" | [`metrics/conformance-view/`](metrics/conformance-view/) |

공식 자산과의 차별점: Gateway API conformance suite(자가선언 PASS/FAIL)나 ingress2gateway(기계적 어노테이션 변환)와 달리, 이 벤치마크는 라이브 거동을 실측하고, conformance가 범위 밖으로 두는 벤더 확장 기능(rate limiting, auth, body size)을 포함하며, conformant 구현체 *안에서의* 기능폭 격차를 비교한다.

각 뷰는 짧은 소개(`README.md`), GitHub에서 바로 렌더되는 전체 표(`README_tables.md`), 인터랙티브 버전(`report.html`)으로 구성된다.

## 무엇을 측정했나

- **7개 구현체**, Gateway API v1.4(experimental 채널 CRD, standard의 상위집합):

  | 구현체 | 버전 | 구현체 | 버전 |
  |---|---|---|---|
  | NGINX Gateway Fabric | 2.4.2 | Kong (KGO) | 2.1 |
  | Envoy Gateway | v1.7.3 | kgateway | v2.2.2 |
  | Istio | 1.30.0 | Traefik | v3.6.17 |
  | Cilium | 1.19.4 | | |

- **채점 conformance**: Core(7) + Extended standard 채널(13) + Extended experimental 채널(1). 공식 모델에 정렬한 라이브 데이터패스 실측으로 채점한다(결정론 항목 3라운드, 가중 라우팅 canary는 동결된 155라운드 풀).
- **conformance 너머**: 벤더 확장 매트릭스(rate-limiting, body-size, regex, tls-passthrough, ip-filter, basic-auth), 비기능 및 운영 지표(load, failover-recovery, health-check, config-robustness), auth 단면(JWT, 외부 인증).
- **마이그레이션 증거**: ingress-nginx 어노테이션별로 ingress2gateway 1.1.0을 직접 실행하고, before/after manifest와 변환 통지를 [`migration/i2gw/`](migration/i2gw/)에 보존했다.

핵심: **7종 전부 Core conformant**다. 갈리는 곳은 Extended 기능폭(13개 중 6개에서 13개)과 conformance가 채점하지 않는 벤더 확장이다. 위 두 뷰가 실측 표를 담는다.

## 저장소 구조

| 경로 | 내용 |
|---|---|
| [`metrics/`](metrics/) | 두 리포트(migration-view, conformance-view) |
| [`scripts/`](scripts/) | 채점 파이프라인(aggregate, score, report)과 `finalize.sh` |
| [`measurement/`](measurement/) | 테스트 하네스(라운드 실행, 테스트 라이브러리, 픽스처) |
| [`implementations/`](implementations/) | 구현체별 설치 스크립트(7종) |
| [`migration/i2gw/`](migration/i2gw/) | ingress2gateway 변환 증거 |
| [`results/`](results/) | 측정 원본 라운드와 집계 |
| `SCORING.md`, `rubric.yaml` | 채점 모델과 동결 rubric(v3) |

## 재현

전체 파이프라인(집계, 채점, 두 뷰 렌더)은 단일 진입점에서 실행한다:

```bash
./scripts/finalize.sh
```

측정 하네스와 구현체별 설치 스크립트는 `measurement/`, `implementations/`에 있다. 채점 모델과 동결 절차는 `SCORING.md`에 정리돼 있다.

## 이전 PoC (v1.2)

이 PoC의 첫 반복(17 tests, Gateway API v1.2, 100라운드)은 [`gateway/v1.2`](https://github.com/sysnet4admin/Research/tree/gateway/v1.2) 브랜치에 보존돼 있다. 현재 브랜치의 결과는 재측정한 Gateway API v1.4 벤치마크(2채널, 벤더 확장, 운영 지표)다.

## 참고

- [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/)
- [ingress2gateway](https://github.com/kubernetes-sigs/ingress2gateway)
- [NGINX Gateway Fabric](https://github.com/nginxinc/nginx-gateway-fabric) / [Envoy Gateway](https://gateway.envoyproxy.io/) / [Istio](https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/) / [Cilium](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/) / [Kong](https://docs.konghq.com/gateway-operator/latest/) / [Traefik](https://doc.traefik.io/traefik/routing/providers/kubernetes-gateway/) / [kgateway](https://kgateway.io/)
