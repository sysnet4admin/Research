# Gateway PoC 채점 설계 (확정 기준)

이 문서는 재측정 채점의 **단일 진실원**이다. 가중치, 레벨 분류, 임계값, 등급
정의는 **재측정 실행 전에 확정**한다. 결과를 보고 기준을 조정하지
않는다(측정 무결성 원칙).

## 1. 배경: 기존 방식과 그 문제

기존 PoC(2025-12-05)는 17개 테스트를 **동등 가중**하고
`PASS / (PASS + FAIL)`(SKIP 제외)로 성공률을 낸 뒤 **A/F 이진** 등급을 매겼다.
round JSON, 집계 스크립트, 점수 파일은 리포에 남지 않아 **재현 불가**였고,
README 공식과 스크립트 공식(`pass/17`)이 서로 달랐다.

구조적 불공정 3가지:

1. SKIP 분모 제외가 "미지원"을 감점 없음으로 만들어 등급을 부풀림
2. 표준에 없는 기능(rate-limiting)과 필수 기능(host-routing)을 동급 처리
3. 100%와 95%를 구분 못 하는 이진 등급

## 2. 채점 모델: 공식 Gateway API conformance 3축

Kubernetes Gateway API의 공식 conformance 체계(Core / Extended /
Implementation-specific)를 기준으로 삼는다. 임의 가중치를 발명하지 않고
업계 표준에 정렬한다.

- **Core**: 모든 구현체가 지원해야 하는 필수 기능. 미지원은 적합성 실패.
- **Extended**: 표준화된 선택 기능. 미지원은 실패가 아니라 "지원 범위"로 투명
  보고. (공식 원칙: 미지원 Extended는 conformance를 실패시키지 않는다.)
- **Implementation-specific**: 벤더 고유 기능. conformance 요건 아님.

### 2.1 측정 축 (3분리)

| 축 | 정의 | 표현 |
|---|---|---|
| **Core 적합성** | 7개 Core 전부 PASS 여부 | Conformant (Yes/No) |
| **Extended 폭** | Extended-standard 중 지원 개수 | breadth = 지원/13 (v3 확장 후 5→13) |
| **Impl-specific 매트릭스** | 비표준 항목 보유 여부 | 별도 기능표(등급 미반영) |

비표준/비기능 4항목(rate-limiting, health-check, load-test,
failover-recovery)은 등급에 넣지 않고 **별도 매트릭스**로만 제시한다. 한 축이
다른 축을 왜곡하지 않게 분리하는 원칙(설계 메모리의 비용 제외 원칙과 동일 논리).

## 3. 17개 테스트 레벨 분류 (v1.4.0 소스로 확정)

kubernetes-sigs/gateway-api v1.4.0 태그의 `pkg/features/`와 `apis/v1/`
필드 Support 주석으로 확정했다. 레벨(Core/Extended)과 채널(standard/experimental)을
분리 표기한다.

| # | 테스트 | 레벨 | 채널@v1.4 | 카테고리 | Gateway API feature |
|---|---|---|---|---|---|
| 1 | host-routing | Core | standard | routing | HTTPRoute hostnames (Support: Core) |
| 2 | path-routing | Core | standard | routing | HTTPRoute path Prefix/Exact (Core) |
| 3 | header-routing | Core | standard | routing | HTTPRoute header match Exact (Core) |
| 4 | tls-termination | Core | standard | tls | Gateway HTTPS listener Terminate (Core) |
| 7 | canary-traffic | Core | standard | traffic | HTTPBackendRef.weight (Core, flag 없음) |
| 12 | header-modifier | Core | standard | modification | RequestHeaderModifier (Core) |
| 13 | cross-namespace | Core | standard | routing | ReferenceGrant (Core) |
| 5 | https-redirect | Extended | standard | tls | HTTPRouteSchemeRedirect/PortRedirect |
| 11 | url-rewrite | Extended | standard | modification | HTTPRoutePathRewrite/HostRewrite |
| 9a | timeout (of #9) | Extended | standard | traffic | HTTPRouteRequestTimeout/BackendTimeout |
| 6 | backend-tls | Extended | standard | tls | BackendTLSPolicy (v1.4서 standard 승격) |
| 14 | grpc-routing | Extended | standard | routing | GRPCRoute (별도 GRPC 프로파일의 Core) |
| 9b | retry (of #9) | 실험 | experimental | traffic | retry 필드만, **v1.4 conformance flag 없음** |
| 10 | session-affinity | 실험 | experimental | traffic | SessionPersistence 필드만, **v1.4 flag 없음** |
| 8 | rate-limiting | Impl-specific | n/a | (매트릭스) | Gateway API 표준 아님 |
| 15 | health-check | Impl-specific | n/a | (매트릭스) | 표준 아님 |
| 16 | load-test | 비기능(성능) | n/a | (매트릭스) | feature 아님 |
| 17 | failover-recovery | 비기능(신뢰성) | n/a | (매트릭스) | feature 아님 |

집계: **Core 7** (필수 HTTP 프로파일), **Extended-standard 13**(v3 확장 후 5→13:
초기 5종 https-redirect/url-rewrite/timeout/backend-tls/grpc-routing + 추가 8종
response-header-modifier/request-mirror/method-matching/query-param-matching/
backend-request-header-mod/path-redirect/websocket/listener-isolation),
**Extended-experimental 1**(CORS), **실험-experimental**(retry, session-affinity 등),
**비표준/비기능 매트릭스**. 권위 분류는 rubric.yaml의 각 test `level` 필드.

### 잠정 분류 대비 정정 (v1.4 소스로)

1. **backend-tls**: BackendTLSPolicy가 v1.4에서 **standard 채널로 승격**.
   작년 Traefik 실패 원인(v1alpha3 vs v1)이 이 승격으로 해소됨. 여전히 Extended
   레벨(opt-in)이나 안정 채널.
2. **timeout-retry 분리**: timeout(#9a)은 Extended/standard로 conformance flag
   존재. retry(#9b)는 v1.4에 **conformance flag 없는 experimental 필드**라
   적합성 등급이 아니라 역량 보고 항목으로 분리.
3. **session-affinity**: v1.4에 **conformance flag 자체가 없음**(experimental
   필드만). 적합성 항목이 아니라 역량 측정 항목. experimental 채널 설치(9.4) 필요성
   재확인.
4. header-modifier는 **RequestHeaderModifier(Core)** 기준. 응답 헤더 수정
   (ResponseHeaderModifier)은 Extended이므로, 테스트가 응답 헤더까지 보면 그
   부분은 Extended로 별도 표기.

> Extended breadth 산정은 **standard 채널 Extended 5종** 기준. 실험 2종(retry,
> session-affinity)은 breadth에 넣지 않고 별도 역량으로 보고(v1.4 conformance
> flag 부재 반영).

## 4. SKIP 의미 분리 (기존 혼용 해소)

기존은 3가지를 모두 `pass=null`로 뭉쳤다. 분리한다:

| 코드 | 의미 | 채점 처리 |
|---|---|---|
| `unsupported` | 구현체가 그 기능을 설계상 미제공 | Core면 FAIL, Extended면 breadth 미포함(감점 아님) |
| `not-configured` | 하네스가 CRD를 안 깔아 미검증 | **버그**. 하네스에서 구성하고 재측정. 점수 아님 |
| `infra-excluded` | 엔드포인트 도달 실패 등 인프라 플레이크 | 평가 제외, 재실행 대상(인프라 제외 정책) |

## 5. 라운드 집계와 합격 임계값

샘플링 테스트(canary, rate-limit, load)는 플레이크가 있어 N라운드 반복한다.

- **Core**: 항목별 라운드 통과율 **100% 요구**. Core가 플레이크면 실제 버그로
  본다. 단일 플레이크가 항목을 떨어뜨리며, 분산을 함께 보고.
- **Extended / 비기능**: 라운드 통과율 + 분산을 **그대로 보고**(이진 강제 안 함).

집계는 `aggregate.py`가 `rounds/*.json`에서 항목별 통과율/분산을 계산한다.
수작업 집계를 코드로 대체한다.

## 6. 산출 구조 (측정/채점/집계/리포트 분리)

```
gateway-PoC/
  SCORING.md               # 이 문서. 확정 기준
  rubric.yaml              # graded 항목 레벨/카테고리/합격기준/임계값 (기계 판독, v3)
  measurement/             # 측정 하네스 → round-N.json(원시 결과+메타)
    run-round.sh, lib-tests.sh, config.sh, manifests/
  implementations/         # 구현체별 install.sh (7종)
  scripts/
    aggregate.py           # rounds/*.json → aggregated.json(통과율/분산)
    merge_canary.py, merge_ops.py  # 분리 캠페인(canary 풀/운영 테스트) 병합
    score.py               # aggregated.json + rubric.yaml → scores.json(항목 판정)
    report.py              # → 두 뷰 README_tables.md(+ 로컬/블로그용 report.html)
    finalize.sh            # 위 단계 일괄 실행(단일 진입점)
  results/
    rounds/round-N.json    # 원시, 커밋(경량)
    aggregated.json, scores.json
  metrics/
    conformance-view/, migration-view/   # 두 뷰(README + 표, 영어/한국어)
```

원시 측정과 채점을 분리하면 임계값 변경 시 재측정 없이 재채점된다. 기존의
"한 bash + 수작업" 결합이 재현 불가의 원인이었다.

## 7. 구현 시 반드시 고칠 결함 (기존 스크립트)

1. grpc-routing 폴백이 백엔드 "존재"만으로 PASS 반환(약 1180행). 실제 gRPC
   호출 성공을 요구하도록 수정.
2. README 공식과 스크립트 공식 불일치 해소(단일 공식으로 확정).
3. 약한 데이터플레인 검증 강화 또는 정직 표기: backend-tls는 사이드카 존재만
   확인(실제 암호화 미검증), session-affinity는 sticky 백엔드 동일성 미확인.
4. 하드코딩(IP .11~.17, 호스트명, 백엔드 응답 문자열) 설정 주도로 분리.

## 8. 확정 절차

레벨 분류(3장), SKIP 정책(4장), 임계값(5장)을 재측정 **전에** 확정한다.
확정 후에는 결과를 보고 변경하지 않는다. 변경이 필요하면 사유를 기록하고
재측정을 새 기준으로 다시 돈다.

## 9. 대상 버전과 구현체 지원 현황 (2026-06 조사로 확정)

### 9.1 target = Gateway API v1.4 (확정)

스펙 최신은 v1.5.1(2026-02)이나 재측정 target은 **v1.4**로 확정한다.
근거: 7개 구현체의 공식 conformance 리포트(kubernetes-sigs/gateway-api)를 교차검증한
결과, **7종이 공통으로 안정 릴리스로 conformance를 갖는 최고 버전이 v1.4**다.
2026-06-12 재확인 기준, NGF, Envoy, Istio, Kong, Traefik은 안정 릴리스로 v1.5.1 공식
conformance를 받았으나 **Cilium(안정 1.19.x=v1.4)과 kgateway(안정 2.1=v1.4, v1.5는
2.3 베타)는 안정 공식 최고가 여전히 v1.4**다. v1.5로 올리면 이 둘은 안정 근거 없이
측정하는 셈이라 비교 공정성이 깨진다. test-cluster의 Cilium 1.19.4(=v1.4 라인)와도
일치한다. 작년 v1.2.0(Cilium 1.18.4까지)에서 한 단계 상향.

> 측정 시점(2026-06)엔 Istio와 Cilium 모두 v1.5 공식 리포트가 없었다. 이후 Istio
> 1.30이 v1.5.1을 받았으나(2026-06-12 확인), 안정 공통 최고 버전이 v1.4라는 결론은
> Cilium과 kgateway 때문에 그대로 유효하다.

### 9.2 구현체별 공식 Gateway API conformance (2026-06-12 확인)

| 구현체 | 공식 conformance 최고 Gateway API | 안정 릴리스 여부 |
|---|---|---|
| NGINX Gateway Fabric | v1.5.1 (NGF 2.6) | 안정 |
| Envoy Gateway | v1.5.1 (EG 1.8) | 안정 |
| Istio | v1.5.1 (Istio 1.30) | 안정 |
| Kong (KGO) | v1.5.1 (KGO 2.2) | 안정 |
| Traefik | v1.5.1 (Traefik 3.7) | 안정 |
| Cilium | v1.4.0 (안정 1.19.x) | v1.5.1은 1.20 pre-release(GA ~7월 말 예상) |
| kgateway | v1.4.0 (안정 2.1) | v1.5.1은 2.3 베타 |

> 출처: kubernetes-sigs/gateway-api `conformance/reports/`의 실제 리포트 파일. **안정 릴리스로 v1.5.1을 받지 못한 건 Cilium과 kgateway뿐**이라, 7종 공통 안정 최고 버전이 v1.4다.

> **버전 skew 주의**: 각 구현체는 릴리스당 Gateway API 한 버전에 핀되고, Kubernetes 같은 N±1 skew 정책이 없다. 컨트롤러가 지원하는 범위보다 CRD 버전을 올리면 새 리소스가 컨트롤러에 무시되거나 미검증 상태가 될 수 있다(구버전 컨트롤러가 너무 새 CRD 버전을 "above maximum, ignoring"으로 건너뛰는 동작을 재현으로 확인). 올리기 전 각 구현체 릴리스 노트의 Gateway API 지원 버전을 확인할 것. 이 표의 conformance 버전은 공식 리포트를 인용한 것이다.

작년 PoC의 두 결함은 해소됨: Traefik는 v3.6+에서 BackendTLSPolicy가 v1 standard로
승격되며 Gateway Ready/포트 문제 해결. kgateway는 v2.2+에서 arm64 지원(v2.3 클린).

### 9.3 Kong 처리 (확정: v1.4에서 그대로 측정)

Kong은 공식 conformance를 KGO 2.1(v1.4.1)과 2.2(v1.5.1)로 받았다(이전 2.0은
v1.3.0 부분통과). 우리는 다른 6종과 동일한 v1.4 선에서 **KGO 2.1(managed gateway)**로
측정한다. 구버전 KIC(unmanaged) 대신 신규 KGO managed gateway 경로로 설치하고,
작년 F의 원인이던 all-or-nothing config 푸시는 기능별 라우트 격리로 측정한다.

### 9.4 CRD 채널 (권고: experimental)

v1.4 **experimental 채널**(standard 상위집합)로 설치한다. session-affinity
(BackendLBPolicy), timeout-retry 일부, TLSRoute 인접 기능이 v1.4에선 experimental
채널에만 있어, standard만 깔면 해당 항목 테스트가 불가능하다. 또 Istio/Traefik/
kgateway/Cilium이 실제 experimental 채널로 conformance를 제출한다. 운영이 아닌
역량 측정이 목적이므로 실험 필드 불안정성은 허용된다. 각 항목이 v1.4에서
standard냐 experimental이냐는 rubric.yaml의 tests에 라벨로 기록해, "standard
적합성"과 "experimental 포함 폭"을 분리해 읽는다.

> Cilium 1.19.x의 v1.4 conformance는 experimental 채널로 제출됨(확인 완료). target=v1.4
> 판정은 채널과 무관하게 유효(Cilium 안정 최고 버전이 v1.4).

## 10. 구현체 선정 (2026-06 확정)

### 10.1 선정 철학: 시장 대표성 + 벤더 비종속 필터

작년(2025-12)과 동일하게 **시장 대표성/인기**를 주 기준으로 유지한다. 이게
공식 conformance 목록과 이 PoC를 가르는 고유 가치다. 공식 목록은 "누가
적합한가"만 알려줄 뿐 "내가 쓰던 인기 제품으로 옮겨도 되는가"는 답하지 않는다.
후자가 이 PoC의 존재 이유다. 따라서 미성숙 제품(Kong 등)도 일부러 포함하고,
그 준비도를 결과로 기록한다(선택 편향 회피).

여기에 **벤더 비종속(자체 호스팅 가능) 필터**를 더한다. 클라우드 매니지드
게이트웨이(GKE/EKS/AWS LBC/Azure)는 마이그레이션 가이드에서 크게 추천되지만
특정 클라우드에 종속되어 제외한다. 즉 이 PoC의 스코프는 **자체 호스팅 +
벤더 비종속 세그먼트**이며, 클라우드 매니지드 다수는 범위 밖임을 명시한다.

### 10.2 재앵커링: ingress-nginx 은퇴 (2026-03)

가장 널리 쓰이던 ingress-nginx가 2026-03 EOL(클러스터 약 50% 영향), 공식 경로는
Gateway API, SIG-Network가 ingress2gateway 1.0 배포(2026-03). 즉 "ingress-nginx
떠나 어느 Gateway API 구현체로 갈까"가 현재 실무의 핵심 질문이다. 재측정 동기를
이 사건에 명시적으로 앵커링한다.

### 10.3 확정 집합 (7종)

작년 7종을 유지한다. 두 독립 시장 조사가 정확히 이 7종을 대표 코어로 수렴 검증했다.

| 구현체 | 데이터플레인 | 대표성 근거 |
|---|---|---|
| Istio | Envoy | Graduated, 메시+게이트웨이 1위, 중립 가이드 최다 언급 |
| Cilium | eBPF | Graduated, CNCF가 ingress-nginx 대체로 직접 지목(2026-01) |
| Envoy Gateway | Envoy | 모멘텀 최고 신생 GW-API, CNCF 마이그레이션 글(2026-05) |
| NGINX Gateway Fabric | nginx | F5의 NGINX Ingress 공식 후속, 직접 이행 경로 |
| kgateway | Envoy | Gloo 7년 프로덕션 계보, 전용 마이그레이션 가이드 최다 |
| Traefik | Go(traefik) | 강력한 #2 Ingress, drop-in 포지셔닝 |
| Kong | OpenResty/nginx | API/AI 게이트웨이 1위. API GW 카테고리 대표. Partial/Stale은 결과로 기록 |

### 10.4 제외 결정과 근거

| 제외 | 근거 |
|---|---|
| GKE, EKS, AWS LB Controller, Azure App GW | 클라우드 종속(스코프 밖) |
| **HAProxy** | k8s Ingress 컨트롤러로는 하위권(GitHub 852 스타, ingress-nginx의 ~1/23). conformant인 커뮤니티 haproxy-ingress는 마이그레이션 가이드에 추천 목적지로 전무. 독립 LB로는 거인이나 시장 대표 Ingress 아님 |
| **Gloo Gateway** | 1차 출처 확인: v2.0+부터 **kgateway OSS 코어 위의 상용 에디션**(v2.1서 "Solo Enterprise for kgateway"로 개명), 라이선스 제품. OSS Gloo 리포는 kgateway로 deprecate 예정. 동일 Envoy 데이터플레인+계보라 중복. 공식 목록서 kgateway(v1.4 적합)가 Gloo(v1.1 부분)보다 앞섬. kgateway가 그 계보의 OSS 대표 |
| Contour | 벤더 비종속이나 Envoy 데이터플레인 중복, 모멘텀 하락(eclipsed), 마이그레이션 가이드 존재감 약함. 추후 필요 시 8번째 후보 |
| Calico | OSS지만 내부적으로 Envoy Gateway 구동(중복) |
| Agentgateway / Airlock / Varnish | AI 특화 / WAAP 벤더 / 캐시 반벤더 (범용 north-south 대표 아님) |

### 10.5 데이터플레인 다양성 (참고)

필드 다수가 Envoy 공유(Envoy GW, Istio, kgateway). 확정 7종은 nginx, eBPF,
Go(traefik), OpenResty(Kong), Envoy 계열로 데이터플레인이 다양하다. 향후 확장 시
독자 데이터플레인 우선이 정보가치가 높다.

> LB IP: 7종이므로 MetalLB 풀은 192.168.1.11-17.
