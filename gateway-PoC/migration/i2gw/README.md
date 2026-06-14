# ingress2gateway 변환 실측 (i2gw 컬럼 근거)

출발점 뷰의 **i2gw 변환** 컬럼은 추정이 아니라 **ingress2gateway를 어노테이션별로 직접 실행한 실측**이다.
각 ingress-nginx 어노테이션에 대해 before(Ingress) / after(Gateway API 변환 출력) / 통지 로그를 보존한다.

## 도구
- ingress2gateway **1.1.0** (`brew install ingress2gateway`)
- provider: `ingress-nginx`

## 재현
```bash
python3 verify.py          # ingress/·gateway/·logs/·results.json 재생성
```

## 구조
| 경로 | 내용 |
|---|---|
| `ingress/<cap>.yaml` | BEFORE: 어노테이션별 샘플 Ingress |
| `gateway/<cap>.out.yaml` | AFTER: `ingress2gateway print` stdout(변환된 Gateway API) |
| `logs/<cap>.txt` | stderr: 변환 통지(WARN/INFO, 미변환 사유) |
| `results.json` | 항목별 분류 + 미변환 어노테이션/사유 |

## 분류 기준
- **native**: 어노테이션 없는 기본 Ingress 필드(host/path/tls/websocket). 기본 변환됨.
- **converts(✓)**: 어노테이션이 Gateway API 등가물로 변환됨, 거절/주의 통지 없음.
- **partial(~)**: 변환되나 (a) 일부 어노테이션 거절, 또는 (b) 의미차 INFO 주의(예: regex 대소문자), 또는 (c) 값 비충실(timeout).
- **no(✗)**: i2gw가 등가물 없다고 거절("Unsupported annotation" 또는 "Failed to apply ... : 사유").

## 실측이 연구 추정과 달랐던 항목(7건)
초판 i2gw 값은 ingress2gateway 1.0 릴리스 블로그/소스 기반 추정이었고, 1.1.0 직접 실행으로 교정됨:

| 항목 | 추정 | 실측 | 근거(로그/출력) |
|---|---|---|---|
| HTTPS 리다이렉트 | converts | **partial** | ssl-redirect는 변환, force-ssl-redirect 거절 |
| URL rewrite | converts | **partial** | URLRewrite 생성되나 regex 대소문자 INFO 주의 |
| regex 경로 | converts | **partial** | RegularExpression 생성되나 대소문자 INFO(silent-404 위험) |
| backend 재암호화 | converts | **partial** | backend-protocol:HTTPS 단독 거절(proxy-ssl-* 전체 필요), 전체 제공 시만 BackendTLSPolicy |
| gRPC 라우팅 | partial | **converts** | GRPCRoute 생성 |
| **TLS passthrough** | **no** | **converts** | ssl-passthrough → TLSRoute(mode:Passthrough) 생성 |
| IP allow/deny | partial | **no** | "IP-based authorization is not supported" 거절 |

## 다중 에이전트 재감사 정정 (2026-06-08)

독립 검증(다중 에이전트 교차 평가)에서 classify() 거절탐지 결함과 샘플 결함을 찾아 정정함. verify.py 재실행 후 증거 기준 확정:

| 항목 | 정정 전 | 정정 후 | 사유 |
|---|---|---|---|
| 세션 어피니티 | partial | **no** | classify가 "failed to parse ... is not supported" 거절을 못 잡아 3개 중 1개만 declined로 기록했음. 보강 후 3개 전부 거절 확인, 출력에 어피니티 0 |
| 헤더 수정 | partial | **no** | x-forwarded-prefix가 출력에 필터 없이 조용히 누락(거절 통지 없음). FINAL 수동 보정 |
| 카나리(가중치) | converts | **converts(유지)** | base/canary가 같은 서비스라 분할이 안 보였던 것. 다른 백엔드(echo-canary)로 분리하니 echo:80 + echo-canary:20 분할 정상 생성, converts 입증 |

classify() 보강: 거절 문구에 `failed to parse`, `is not supported`, `failed strict validation` 추가, 어노테이션 키 단어경계 매칭으로 substring 충돌 방지.

## 한계
- 샘플은 어노테이션당 최소 Ingress. 일부는 어노테이션 조합/추가 필드에 따라 결과가 달라질 수 있음(예: backend-tls는 proxy-ssl-* 전체 제공 시 변환).
- 헤더 수정은 x-forwarded-prefix가 조용히 누락되고 proxy-set-headers/custom-headers도 미변환이라 no로 확정.
- JWT는 ingress-nginx에 전용 어노테이션이 없어(snippet/플러그인 경유) i2gw 변환 대상이 아님. snippet 자체는 별도 행에서 측정(no).
- mtls-client는 실측함(2026-06-10 추가): `auth-tls-secret`/`auth-tls-verify-client`/`auth-tls-verify-depth` 3종 모두 "Unsupported annotation" 거절(no). 점검표 mTLS 행 i2gw `✗`의 측정 근거.
