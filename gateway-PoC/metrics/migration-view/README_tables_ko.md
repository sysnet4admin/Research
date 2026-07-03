# Gateway API PoC 출발점 뷰 (ingress-nginx → Gateway API v1.4 마이그레이션)

> **Gateway API 공식 권고는 'conformant 인증을 받은 구현체를 고르라'는 것이다. 하지만 conformant 인증을 받아도 실제 지원하는 기능 폭은 6개에서 13개까지 갈린다. 그 차이를 비교하는 것이 이 뷰다.**

> **이 뷰의 차별점**: 공식 conformance(선언 PASS/FAIL), ingress2gateway(기계 변환 여부)와 달리, 라이브 클러스터 **실측** + conformance 범위 밖 **구현체 기능**(rate-limit, auth, body-size) + conformant 내부의 **기능폭 격차**를 같은 잣대로 나란히 비교한다. 엄밀성(스펙) 뷰는 `../conformance-view/` 참조.

> **측정 기준: Gateway API v1.4** (2026-06 측정 시점, ingress2gateway 1.1.0). 난이도 등급은 이 버전 기준이다. **v1.5(2026-04-21 릴리스) 신규 기능**(mTLS 클라이언트 등)은 v1.4 측정 범위 밖이라 `TBD(v1.5)`로 표기하고 차기 재베이스라인 대상이다(재베이스라인은 Cilium 1.20 stable, 7월 말 예정 이후). 반면 **CORS, 외부 인증, TLSRoute는 v1.4 experimental 채널에서 이미 7종 실측**했으며, v1.5에서 표준 채널로 승격되면 🟡→🟢으로 올라갈 수 있다. 셀 값 출처는 엄밀성 뷰의 실측과 동일(같은 측정 데이터).

## 1. 마이그레이션 난이도 4등급

| 등급 | 의미 |
|---|---|
| **🟢 표준 마이그레이션** | Core/Extended-std, i2gw 자동변환, 표준채널 안정. 대체로 그대로 전환 |
| **🟡 주의 마이그레이션** | 실험채널이거나 의미가 달라 검증 필수. v1.5에서 다수 승격 예정 |
| **🟠 벤더 종속** | 표준 API가 없어 각 구현체의 CRD로만 구현 가능. 특정 구현체에 묶이는 벤더 락인(vendor lock-in) 발생 |
| **🔴 마이그레이션 불가** | 등가물 자체 없음(재설계 필수) |

## 2. 구현체별 커버리지 (측정 가능 항목 기준)

> *"내 ingress-nginx를 이 구현체로 옮기면 등급별로 몇 개가 실제 동작하나."* 구현체별로 실제 측정한 항목만 센다. 🔴 마이그레이션 불가 등급과, 구현체와 무관하게 Gateway API 스펙 수준에서만 판정한 항목(표에서 `(미측정)`), 그리고 측정 매핑이 없는 구조적 행(예: mTLS 클라이언트=`TBD(v1.5)`)은 제외한다. 그래서 등급별 분모가 3절 점검표의 행 수보다 작을 수 있다(예: 🟡은 점검표 8행 중 mTLS를 뺀 7개 기준).

| 구현체 | 🟢 표준(11) | 🟡 주의(7) | 🟠 구현체(6) | 합계 |
|---|---|---|---|---|
| nginx | 11/11 | 5/7 | 3/6 | **19/24** |
| envoy | 11/11 | 7/7 | 5/6 | **23/24** |
| istio | 11/11 | 6/7 | 4/6 | **21/24** |
| cilium | 11/11 | 4/7 | 0/6 | **15/24** |
| kong | 8/11 | 1/7 | 3/6 | **12/24** |
| kgateway | 11/11 | 6/7 | 4/6 | **21/24** |
| traefik | 10/11 | 5/7 | 4/6 | **19/24** |

> 지원 = **동작**(low-level-config/snippet 저수준 포함). 동작 여부만 세고 품질차(native vs 저수준)는 3절 상세표가 보여준다. 외부 auth는 구현체 native 기준(GEP-1494 표준 필터는 아무도 강제 못 함, 엄밀성 뷰 7절).

## 3. 마이그레이션 점검표 (26개, 난이도 그룹)

> **범례: i2gw 변환**(ingress2gateway 1.1.0을 어노테이션별로 **직접 실행한 실측**, before/after manifest는 `migration/i2gw/`): `✓` 자동변환 / `~` 부분/best-effort(또는 일부 어노테이션 거절) / `✗` 미변환(수동 재설계) / `native` Ingress 기본기능이라 변환 대상 아님(가장 쉬움). **변환됨 ≠ 동작함**. 구현체 셀(PASS/native 등)이 실제 지원을 보여준다.

### 🟢 표준 마이그레이션 (11)

| 기능 | ingress-nginx 어노테이션 | 중요도 | GW API v1.4 | i2gw | nginx | envoy | istio | cilium | kong | kgateway | traefik |
|---|---|---|---|---|---|---|---|---|---|---|---|
| host 라우팅 | `(native Ingress rules)` | 상 | Core | native | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| path 라우팅 | `(native rules, pathType)` | 상 | Core | native | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| header 라우팅 | `canary-by-header` | 중 | Core | ✓ | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| TLS 종료 | `(native tls.secretName)` | 상 | Core | native | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| HTTPS 리다이렉트 | `ssl-redirect, force-ssl-redirect` | 상 | Core(RequestRedirect) | ~ | PASS | PASS | PASS | PASS | FAIL | PASS | PASS |
| path 리다이렉트 | `permanent-redirect, temporal-redirect, app-root` | 중 | Core/Ext(RequestRedirect) | ✓ | PASS | PASS | PASS | PASS | FAIL | PASS | PASS |
| URL rewrite | `rewrite-target` | 상 | Extended-std(URLRewrite) | ~ | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| 카나리(가중치) | `canary, canary-weight, canary-weight-total` | 상 | Core(weighted backendRefs) | ✓ | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| 요청 미러링 | `mirror-target, mirror-host` | 하 | Extended-std(RequestMirror) | ✗ | PASS | PASS | PASS | PASS | n/a | PASS | FAIL |
| 헤더 수정(요청/응답) ※ | `proxy-set-headers, custom-headers, x-forwarded-prefix` | 상 | Core(요청)/Ext(응답) | ✗ | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| websocket | `(native, proxy upgrade)` | 중 | Extended-std(WebSocket) | native | PASS | PASS | PASS | PASS | PASS | PASS | PASS |

> ※ 함정/주석:
  - **헤더 수정(요청/응답)**: x-forwarded-prefix는 출력에 필터 없이 조용히 누락(거절 통지도 없음), proxy-set-headers/custom-headers도 미변환. i2gw 실측 결과 등가물 방출 0

### 🟡 주의 마이그레이션 (8)

| 기능 | ingress-nginx 어노테이션 | 중요도 | GW API v1.4 | i2gw | nginx | envoy | istio | cilium | kong | kgateway | traefik |
|---|---|---|---|---|---|---|---|---|---|---|---|
| regex 경로 ※ | `use-regex + capture group` | 상 | impl-specific(RegularExpression) | ~ | supported | supported | supported | supported | supported | supported | supported |
| timeout ※ | `proxy-connect/read/send-timeout` | 상 | Standard(v1.2) | ~ | FAIL | PASS | PASS | PASS | FAIL | PASS | FAIL |
| CORS ※ | `enable-cors, cors-allow-*, cors-expose-headers, cors-max-age` | 상 | Extended-exp(v1.4) | ✓ | n/a | PASS | PASS | FAIL | n/a | PASS | FAIL |
| 외부 인증(OIDC 포함) ※ | `auth-url, auth-signin, auth-snippet` | 상 | Extended-exp(GEP-1494, v1.4) | ✗ | SnippetsFilter 저수준 | SecurityPolicy native | AuthzPolicy CUSTOM(mesh) | 미지원 | OSS 미지원 | GatewayExtension native | forwardAuth native |
| backend 재암호화 | `backend-protocol: HTTPS, proxy-ssl-*` | 중 | Core(BackendTLSPolicy GA v1.4) | ~ | PASS | PASS | PASS | FAIL | FAIL | FAIL | PASS |
| gRPC 라우팅 | `backend-protocol: GRPC` | 중 | Core(GRPCRoute 별도) | ✓ | PASS | PASS | PASS | PASS | FAIL | PASS | PASS |
| mTLS 클라이언트 인증 ※ | `auth-tls-secret, auth-tls-verify-client, auth-tls-verify-depth` | 중 | v1.4 미제공, v1.5(2026-04)에서 추가 | ✗ | TBD(v1.5) | TBD(v1.5) | TBD(v1.5) | TBD(v1.5) | TBD(v1.5) | TBD(v1.5) | TBD(v1.5) |
| TLS passthrough ※ | `ssl-passthrough` | 중 | Extended-exp(TLSRoute) | ✓ | supported | supported | unsupported | supported | unsupported | supported | supported |

> ※ 함정/주석:
  - **regex 경로**: nginx은 prefix 매치에 대소문자 무시, GW는 풀매치에 대소문자 구분이라 그대로 옮기면 silent 404 위험(Before You Migrate). capture-group rewrite는 대부분 미지원
  - **timeout**: nginx의 timeout 3개를 GW의 request/backendRequest 2개로 합쳐야 함, i2gw는 best-effort 변환
  - **CORS**: 실험채널, v1.5에서 Standard 승격 예정
  - **외부 인증(OIDC 포함)**: OIDC는 보통 auth-url에서 oauth2-proxy로 구현하므로 이 행에 포함. mTLS 클라이언트 인증과 함께 v1.5 GA 목표
  - **mTLS 클라이언트 인증**: 표준 frontendValidation 필드가 v1.4 Gateway CRD에 아예 없음(experimental v1.4.1 CRD 직접 확인: tls는 certificateRefs/mode/options뿐). v1.5(2026-04-21 릴리스, GEP-91)에서 frontendValidation.caCertificateRefs로 추가됨(AllowValidOnly/AllowInsecureFallback). 우리 벤치마크는 v1.4 고정이라 미측정 → TBD(v1.5). Cilium 1.20 stable(7월 말 예정) 이후 v1.5 재베이스라인 시 측정 가능
  - **TLS passthrough**: TLSRoute(passthrough)로 7종 실측. TLSRoute v1.5 GA 목표(PR #4064)

### 🟠 벤더 종속 (6)

| 기능 | ingress-nginx 어노테이션 | 중요도 | GW API v1.4 | i2gw | nginx | envoy | istio | cilium | kong | kgateway | traefik |
|---|---|---|---|---|---|---|---|---|---|---|---|
| rate limiting | `limit-rps, limit-rpm, limit-connections, limit-rate, limit-whitelist` | 상 | 표준 없음 → 구현체 정책 CRD | ✗ | native | native | low-level-config | unsupported | native | native | native |
| 요청 본문 크기 제한 | `proxy-body-size` | 상 | 표준 없음(i2gw도 경고) | ✗ | native | unsupported | low-level-config | unsupported | native | unsupported | native |
| 세션 어피니티 ※ | `affinity: cookie, session-cookie-name/expires` | 중 | 스펙 있으나 cookie설정 impl종속 | ✗ | n/a | PASS | n/a | n/a | n/a | PASS | n/a |
| JWT 검증 | `(auth-snippet / 플러그인)` | 상 | 표준 없음 → 구현체 | ✗ | Plus전용(OSS는 Basic만) | native JWKS | native JWKS | 미지원 | KGO 시크릿이슈(거부만) | native JWKS | 미지원 |
| IP allow/deny ※ | `whitelist-source-range, denylist-source-range` | 중 | 표준 필터 없음 → 구현체 정책 | ✗ | unsupported | native | native | unsupported | native | unsupported | native |
| basic auth ※ | `auth-type: basic, auth-secret, auth-realm` | 중 | 표준 없음 → 구현체 정책 | ✗ | native | native | unsupported | unsupported | unsupported | native | native |

> ※ 함정/주석:
  - **세션 어피니티**: i2gw 실측 결과 affinity/session-cookie-* 3개 전부 거절(Session affinity is not supported), 출력에 어피니티 구성 0
  - **IP allow/deny**: 구현체 CIDR 정책으로 7종 실측. i2gw는 impl-specific config로만 방출
  - **basic auth**: 표준 Gateway API엔 없으나 구현체가 구현(envoy SecurityPolicy, traefik/kong, NGF AuthenticationFilter)해 🟠로 분류. 7종 실측

### 🔴 마이그레이션 불가 (1)

| 기능 | ingress-nginx 어노테이션 | 중요도 | GW API v1.4 | i2gw | nginx | envoy | istio | cilium | kong | kgateway | traefik |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 설정 스니펫 ※ | `configuration-snippet, server-snippet, stream-snippet` | 상 | 설계상 등가물 없음(IngressNightmare 원인) | ✗ | (미측정) | (미측정) | (미측정) | (미측정) | (미측정) | (미측정) | (미측정) |

> ※ 함정/주석:
  - **설정 스니펫**: 실사용됨(커스텀 헤더, 타임아웃, 버퍼 크기, 경로 차단 등). 단 그 용례 다수는 이미 타입드 기능에 흡수(헤더 수정/timeout 등 다른 행에서 측정). 잔여 본질인 임의 nginx 지시문 주입은 표준도 안전한 구현체 대체물도 없어 측정 무의미(측정 대상 아님). v1.9.0부터 보안상 기본 비활성화(CVE-2021-25742). NGF에만 snippet 옵션 잔존(그 CVE의 원인 기능)

## 4. 읽는 법 / 출처 / 한계

- **셀 읽기**: 🟢🟡 등급은 실측 `PASS/FAIL/n/a`. 🟠 구현체는 `native/low-level-config/unsupported` 매트릭스. auth는 라이브 검증값(엄밀성 7절). `(미측정)`은 구현체별로 측정하지 않고 Gateway API 스펙 수준에서만 판정한 항목(예: snippet은 어느 구현체든 등가물이 없음).
- **i2gw 변환**: ingress2gateway 1.1.0을 어노테이션별 샘플 Ingress로 **직접 실행**해 변환 결과/경고를 기록한 **실측값**(연구 추정 아님). before/after manifest + 로그 + 분류 근거는 `migration/i2gw/`(ingress/, gateway/, logs/, results.json). `✓`=자동변환, `~`=부분/일부 거절, `✗`=미변환(수동 재설계), `native`=Ingress 기본기능이라 변환 대상 아님.
- **점검표에서 제외한 것**: method 매칭, query-param 매칭처럼 ingress-nginx에 없던 Gateway API 신규 표준 기능은 이 점검표에 넣지 않았다. 마이그레이션으로 "넘어갈 것"이 아니라 옮긴 뒤 추가로 얻는 기능이기 때문이다(엄밀성 뷰에서 측정).
- **중요도(상/중/하)**: ingress-nginx 실사용 중요도. directional이다. 공개 정량 survey가 없어, 메인테이너가 snippet을 "가장 의존+가장 위험"으로 지목한 신호와 마이그레이션 가이드 강조를 종합했다.
- **출처(1차)**: ingress-nginx 은퇴 발표(2025-11-11), "Before You Migrate"(2026-02-27), ingress2gateway 1.0(2026-03-20), IngressNightmare CVE-2025-1974, Reddit "Gateway API for Ingress-NGINX, a Maintainer's Perspective".
- **한계**: 🟡 다수(CORS, 외부 인증, mTLS 클라이언트, TLSRoute)는 v1.4 실험채널이며 v1.5에서 Standard 승격 예정 → 시점에 따라 등급 상향 가능. 🔴 snippet은 설계상 영구 미지원(재설계 필수).
