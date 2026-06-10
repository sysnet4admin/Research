# Gateway API PoC 엄밀성 뷰 (Gateway API v1.4, 결정론 3 rounds, canary 155라운드 풀)

> **라운드 근거**: 결정론(determinstic) 항목은 v3 캠페인 3라운드, canary(가중 라우팅)는 동결된 155라운드 풀이다(발표 메트릭 동결). 두 축의 라운드 수가 다르며, 섹션 2의 canary 행 판정은 155라운드 풀링(섹션 3)에 근거한다.

> 공식 스펙(Core/Extended/채널)에 정렬한 **실측 검증** + conformance가 보지 않는 **품질/비기능 지표**(canary 분포, 부하, 견고성). 출발점(마이그레이션) 뷰는 `../migration-view/` 참조.

## 1. 요약 (conformance)

> 공식 Gateway API conformance는 **채널별**로 채점된다(Core+Extended). 우리는 **experimental 채널 CRD**(standard 상위집합)로 측정하므로 두 채널 모두 본다.

> 채점 = **Core 7**(필수, Support:Core) + **Extended(standard) 13**(안정) + **Extended(experimental) 1**(필드 변경 가능). experimental 필드(conformance 기능 없음), 구현체, 비기능은 비채점(섹션 5~8).

| 구현체 | 버전 | Core (7) | Extended-std (13) | Extended-exp (1) | 미통과 Core |
|---|---|---|---|---|---|
| nginx | 2.4.2 | 7/7 통과 | 11/13 | 0/1 | - |
| envoy | v1.7.3 | 7/7 통과 | 13/13 | 1/1 | - |
| istio | 1.30.0 | 7/7 통과 | 13/13 | 1/1 | - |
| cilium | 1.19.4 | 7/7 통과 | 12/13 | 0/1 | - |
| kong | KGO 2.1 | 7/7 통과 | 6/13 | 0/1 | - |
| kgateway | v2.2.2 | 7/7 통과 | 12/13 | 1/1 | - |
| traefik | v3.6.17 | 7/7 통과 | 10/13 | 0/1 | - |

> **Core N/7 통과**: Support:Core 필수 기능. 전부 통과 = 공식 모델의 "conformant". 선택(Extended) 미지원은 적합성에 무영향.
> **Extended는 채널 2축**: `std`=standard 채널(안정), `exp`=experimental 채널(필드 변경 가능). 둘 다 공식 conformance의 Extended 기능이며 채널만 다르다(GEP-1709: conformance는 채널별 채점). v1.4 experimental Extended는 적어 exp 축은 1항목(CORS 등).
> ⚠️ 이 표는 **공식 모델에 정렬된 자체 데이터패스 측정**이지 upstream 스위트 등재 **공식 인증은 아님** (공식 v1.4.0 리포트와 일치함은 1차소스로 확인).

> **버전 주의(스냅샷)**: 측정 시점 버전 기준이며, 이후 릴리스에서 일부 미지원이 해소됐다 (2026-06-10 공식 conformance/CHANGELOG로 확인). Traefik backend-request-header-mod는 **3.7에서 지원**(측정 3.6.17), kgateway backend-tls는 **2.3.0에서 지원**(측정 2.2.2), Cilium backend-tls/ExternalAuth는 **1.20에서 지원**(측정 1.19.4, 1.20 GA 임박), Kong TLSRoute는 **KGO 2.2.0에서 지원**(측정 2.1.x). 인용 시 측정 버전을 함께 밝힌다.

## 2. 항목별 상세 (채점 21: Core 7 + Extended-std 13 + Extended-exp 1)

| 테스트 | 구분 | nginx | envoy | istio | cilium | kong | kgateway | traefik |
|---|---|---|---|---|---|---|---|---|
| host-routing | Core(필수) | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| path-routing | Core(필수) | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| header-routing | Core(필수) | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| tls-termination | Core(필수) | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| [canary-traffic](#canary-detail) | Core(필수) | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| header-modifier | Core(필수) | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| cross-namespace | Core(필수) | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| https-redirect | Extended-std | PASS | PASS | PASS | PASS | FAIL | PASS | PASS |
| url-rewrite | Extended-std | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| timeout | Extended-std | FAIL | PASS | PASS | PASS | FAIL | PASS | FAIL |
| backend-tls | Extended-std | PASS | PASS | PASS | FAIL | FAIL | FAIL | PASS |
| grpc-routing | Extended-std | PASS | PASS | PASS | PASS | FAIL | PASS | PASS |
| response-header-modifier ◆차별 | Extended-std | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| request-mirror ◆차별 | Extended-std | PASS | PASS | PASS | PASS | n/a | PASS | FAIL |
| method-matching ◇공통 | Extended-std | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| query-param-matching ◇공통 | Extended-std | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| backend-request-header-mod ◆차별 | Extended-std | n/a | PASS | PASS | PASS | n/a | PASS | FAIL |
| path-redirect ◆차별 | Extended-std | PASS | PASS | PASS | PASS | FAIL | PASS | PASS |
| websocket ◇공통 | Extended-std | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| listener-isolation ◇공통 | Extended-std | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| cors ◆차별 | Extended-exp | n/a | PASS | PASS | FAIL | n/a | PASS | FAIL |

> canary는 표본 테스트라 누적 풀링 split(2σ)으로 PASS/FAIL 판정한다. **행 이름 `canary-traffic`을 누르면** 구현체별 세부 split 비율(섹션 3)로 이동한다.
> ◇공통=7종 전부 지원(마이그레이션 안전 보증), ◆차별=구현체별 갈림. v1.4 standard 채널 conformance flag 보유 항목만 graded.

<a id="canary-detail"></a>
## 3. canary 품질 지표 (가중 라우팅 80/20, 풀링)

| 구현체 | 누적 split(v1%) | 표본수 | 라운드 평균 v1 | min~max | 2σ이탈 라운드 |
|---|---|---|---|---|---|
| nginx | 79.4% | 7750 | 39.72 | 32~48 | 8/155 |
| envoy | 80.0% | 7750 | 40.0 | 39~41 | 0/155 |
| istio | 80.0% | 7750 | 39.98 | 32~47 | 8/155 |
| cilium | 79.7% | 7750 | 39.86 | 31~47 | 8/155 |
| kong | 80.0% | 7750 | 39.99 | 38~42 | 0/155 |
| kgateway | 79.9% | 7750 | 39.93 | 31~47 | 7/155 |
| traefik | 80.0% | 7750 | 40.0 | 40~40 | 0/155 |

> **출처**: 결정론 항목은 v3 캠페인 재측정, canary는 기존 155라운드 풀링 보존(발표 메트릭 동결)
> **누적 split(v1%)**: 전 라운드 v1/v2 요청을 합산한 실제 분배 비율(목표 80%). 이게 목표에 2σ 내로 수렴하면 canary PASS.
> **2σ이탈 라운드**: 라운드마다 50요청 중 v1 횟수가 통계적 2σ 구간 **[35,45]**(목표 40±2σ, sigma=2.83이라 정수 구간 35~45)을 벗어난 라운드 수 / 전체. 예 `5/155` = 155라운드 중 5라운드가 구간 밖. 표본 노이즈상 약 5%/라운드는 정상 이탈이라 **실패가 아니라 분포 품질 참고치**다(그래서 판정은 라운드별이 아닌 누적 풀링으로 한다).

## 4. experimental 필드 (conformance 기능 없음, 채점 불가, 역량 보고)

> API에 experimental **필드**로 존재하나 v1.4 conformance **기능(테스트) 자체가 없다**(CORS 같은 experimental Extended와 다름 → 그건 섹션 2에 채점됨).

| 구현체 | retry | session-affinity |
|---|---|---|
| nginx | PASS | n/a |
| envoy | PASS | PASS |
| istio | PASS | n/a |
| cilium | PASS | n/a |
| kong | PASS | n/a |
| kgateway | PASS | PASS |
| traefik | PASS | n/a |

> **retry 상세**(HTTPRoute 표준 retry 필드 `retry.attempts:3,codes:[503]`, 503에 1 요청당 업스트림 시도 수): nginx 3회 시도, envoy 12회 시도, istio 12회 시도, cilium 3회 시도, kong 3회 시도, kgateway 12회 시도, traefik 3회 시도. 시도 수 차이는 구현체 retry 정책(istio/kgateway가 더 공격적). '(일부 라운드 라우팅 실패)'는 해당 구현체가 일부 라운드에서 라우트 프로그래밍에 실패해 그 라운드를 분모에서 제외했다는 뜻.

## 5. 구현체 기능 매트릭스 (Gateway API 표준 외, conformance 무관)

> 표준에 없고 구현체 고유 메커니즘으로 제공. native / low-level-config / unsupported로 비교.

| 구현체 | rate-limiting | body-size | regex | tls-passthrough | ip-filter | basic-auth |
|---|---|---|---|---|---|---|
| nginx | native | native | supported | supported | unsupported | native |
| envoy | native | unsupported | supported | supported | native | native |
| istio | low-level-config | low-level-config | supported | unsupported | native | unsupported |
| cilium | unsupported | unsupported | supported | supported | unsupported | unsupported |
| kong | native | native | supported | unsupported | native | unsupported |
| kgateway | native | unsupported | supported | supported | unsupported | native |
| traefik | native | native | supported | supported | native | native |

> **측정 설정 주의(공정성, 2026-06-10 재검증)**: 일부 항목은 구현체 권장 설정을 켜야 동작한다. Kong은 query-param/method 매칭을 위해 `router_flavor=expressions`로 측정했다(OSS 디폴트 traditional_compatible은 query-param 미지원, 즉 디폴트로 재면 더 낮게 나온다). kgateway basic-auth는 TrafficPolicy basicAuth로 동작(native). Cilium rate-limiting/body-size는 선언형 표준이나 구현체 경로가 없어 unsupported로 적었으나, raw CiliumEnvoyConfig(istio EnvoyFilter와 동급 저수준 escape hatch)로는 가능하다(미측정). Istio tls-passthrough는 alpha 플래그(PILOT_ENABLE_ALPHA_GATEWAY_API)를 켜도 v1.4에서 미동작이라 미지원(istio TLSRoute는 Terminate만 공식 conformant, passthrough 미검증, 이슈 #47366).

## 6. 비기능 / 운영 지표 (기능 아님, 성능, 견고성, 복구)

| 구현체 | health-check | load-test | failover-recovery | config-robustness |
|---|---|---|---|---|
| nginx | n/a | PASS | PASS | robust |
| envoy | PASS | PASS | PASS | robust |
| istio | n/a | PASS | PASS | robust |
| cilium | n/a | PASS | n/a | robust |
| kong | PASS | PASS | PASS | robust |
| kgateway | PASS | PASS | PASS | robust |
| traefik | n/a | PASS | PASS | robust |

> **failover-recovery 상세**(데이터플레인 강제 재시작 후 복구, rounds-ops 별도 캠페인): nginx 복구~13s, envoy 복구~13s, istio 무중단, cilium 측정제외(공유 eBPF), kong 복구~34s, kgateway 무중단, traefik 복구~13s. 무중단=파드 교체 중 트래픽 무손실(outage 0), 복구~Ns=약 N초 공백 후 정상화. 모두 파드 교체(pod_changed)로 교란 확인됨.

> **health-check 상세**(능동 health check가 unhealthy 백엔드를 풀에서 빼는가. good 2 + bad 1(/health 503) 백엔드, bad 완전 제거 시 지원, rounds-ops): nginx 미지원, envoy 지원, istio 미지원, cilium 미지원, kong 지원, kgateway 지원, traefik 미지원. 지원=envoy BackendTrafficPolicy / kong KongUpstreamPolicy / kgateway BackendConfigPolicy의 능동 probe. 미지원=능동 HC 미노출(nginx는 Plus 전용, istio는 mesh outlier, cilium/traefik 미노출).

> **config-robustness 측정 조건**: '모든 기능을 동시에 배포했을 때 기본 라우팅이 살아남는가'. 위 값은 표준 기능셋(결정론 캠페인) 기준이다. kong은 config-load에 민감해, 운영 테스트 정책까지 동시에 얹은 더 무거운 설정(rounds-ops 캠페인)에선 같은 항목이 fragile로 떨어진다. kong의 all-or-nothing 설정 모델 특성과 일치하며, 위 robust 표기는 표준 설정 시나리오 한정이다.

## 7. auth (주제: 구현체/실험 혼재, 마이그레이션 핵심)

> 카테고리가 아니라 **주제 단면**: auth는 분류상 흩어져 있다. **JWT=구현체(섹션 5형, 표준 없음)**, **ext-authz 표준필터=experimental(GEP-1494)**, **ext-authz 구현체=구현체**. ingress-nginx auth-url 마이그레이션 핵심이라 한 곳에 모음. 7종 라이브 검증값(E8, E9), per-round 자동측정 미통합(비채점).

| 구현체 | JWT | ext-authz(구현체) | ext-authz(표준 GEP-1494 필터) |
|---|---|---|---|
| nginx | Plus전용(OSS는 Basic만) | SnippetsFilter 저수준 | 미구현(404) |
| envoy | native JWKS | SecurityPolicy native | 미구현(UnsupportedValue) |
| istio | native JWKS | AuthzPolicy CUSTOM(mesh) | 미구현(InvalidFilter) |
| cilium | 미지원 | 미지원 | 표준필터 미구현(통과)★ |
| kong | KGO 시크릿이슈(거부만) | OSS 미지원 | 미구현(404) |
| kgateway | native JWKS | GatewayExtension native | 표준필터 미구현(통과)★ |
| traefik | 미지원 | forwardAuth native | 수용하나 500 |

> ★ GEP-1494 표준 ExternalAuth 필터는 어떤 구현체도 강제하지 못한다. envoy/nginx/istio/kong/traefik은 거부 또는 오류, cilium/kgateway는 표준 필터를 구현하지 않아 무인증 트래픽이 그대로 통과한다(silent no-op). GEP-1494는 experimental 단계라 실패모드(fail-open/closed)를 규정하지 않는다(스펙에 'MUST fail closed' 문구 없음, PR #4001에서 실패 의미 보류). cilium은 1.20, kgateway는 자체 TrafficPolicy로만 ext-authz를 제공한다. 결론: 표준 필터는 아직 프로덕션 auth로 못 쓰고 구현체 CRD가 필요하다.

## 8. 플레이크 / 데이터 주의 (canary 제외, 섹션 3 참조)

- (현재 비-canary 플레이크 없음)

## 9. 데이터 주의: not-configured (자동 라운드 미통합)

> 자동 라운드 루프에 통합되지 않아 round 데이터가 없는 항목. 두 종류로 갈린다. (a) **auth-jwt/auth-extauth는 측정 완료**다. 라이브 검증(E8/E9)했고 값은 7절 auth 표에 있다. 자동 루프 통합만 보류라 round에는 `미구성`으로 찍힐 뿐 데이터가 없는 게 아니다. (b) **그 외는 미측정**(라이브 로직 부재, 재측정 대상). 모두 비채점이라 등급 무관.

- nginx: 측정완료(E8/E9, 7절 참조): auth-extauth, auth-jwt
- envoy: 측정완료(E8/E9, 7절 참조): auth-extauth, auth-jwt
- istio: 측정완료(E8/E9, 7절 참조): auth-extauth, auth-jwt
- cilium: 측정완료(E8/E9, 7절 참조): auth-extauth, auth-jwt
- kong: 측정완료(E8/E9, 7절 참조): auth-extauth, auth-jwt
- kgateway: 측정완료(E8/E9, 7절 참조): auth-extauth, auth-jwt
- traefik: 측정완료(E8/E9, 7절 참조): auth-extauth, auth-jwt
