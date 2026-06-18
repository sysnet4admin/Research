# 출발점 뷰 (ingress-nginx에서 Gateway API로 마이그레이션)

[English](README.md)

질문: **ingress-nginx를 쓰는데, 각 구현체로 옮기면 뭐가 넘어가고 뭐가 막히나.**

> Gateway API 공식 권고는 "conformance를 통과한(conformant) 구현체를 고르라"는 것이다. 하지만 conformant여도 실제 지원하는 기능 폭은 6개에서 13개까지 갈린다. 그 차이를 비교하는 것이 이 뷰다.

## 산출물
- [`README_tables_ko.md`](README_tables_ko.md) 마이그레이션 점검표 (난이도 4등급, 26항목, 구현체별 커버리지). GitHub에서 바로 렌더되며, 여기서는 이게 정본이다.

> 파이프라인은 블로그 글용으로 스타일링된 단일 페이지 `report_ko.html`(인터랙티브)도 생성하지만, GitHub은 데이터를 마크다운으로 제공하고 HTML은 소스로만 보여주므로 여기엔 커밋하지 않는다. 재생성은 `scripts/finalize.sh`.

## 왜 지금인가 (맥락)
- **ingress-nginx 은퇴 확정** (2025-11-11 발표): 2026년 3월 유지보수 중단, 이후 보안 패치 없음. 후속 컨트롤러 InGate는 무산. 메인테이너 권고는 "Gateway API로 마이그레이션".
- **은퇴 동인**: 1~2명 자원봉사 유지의 한계에 더해, `configuration-snippet`, `server-snippet` 어노테이션이 raw nginx 지시문을 주입하는 설계가 보안 결함이 됨. 그 정점이 IngressNightmare(CVE-2025-1974, CVSS 9.8) 무인증 RCE.
- **ingress2gateway 1.0** (2026-03-20): 30개 넘는 어노테이션을 자동 변환하고, 변환 불가 항목은 경고한다. 이 도구가 사실상 "마이그레이션 자동화 경계선"을 그어준다.
- **"Before You Migrate"** (2026-02-27): regex 의미 차이(prefix 매치, 대소문자 처리), 스니펫, 외부 인증, mTLS 같은 실제 함정을 메인테이너가 직접 정리.

## 난이도 4등급 (점검표의 뼈대)
- 🟢 **표준 마이그레이션**: Core/Extended-std, ingress2gateway 자동 변환, 표준 채널(메인테이너 표현으로 "Ingress만큼 안정"). 대체로 그대로 전환.
- 🟡 **주의 마이그레이션**: 실험 채널이거나 의미가 달라 검증 필수. CORS, 외부 인증, mTLS 클라이언트, TLSRoute는 v1.4 실험 채널이며 v1.5에서 Standard 승격 예정.
- 🟠 **벤더 종속**: 표준 API 없음, 각 구현체의 CRD로만 제공해서 벤더 락인(vendor lock-in)이 재발한다. rate-limit, body-size, JWT가 여기.
- 🔴 **마이그레이션 불가**: Gateway API에 등가물 자체가 없음(설계상 제거). 스니펫, basic auth.

## 이 뷰가 공식 자산과 다른 점
- 공식 **conformance suite**는 "스펙 준수 이진 PASS/FAIL"만, **ingress2gateway**는 "기계적 변환 여부"만, **마이그레이션 가이드**는 고수준이다.
- 이 뷰는 라이브 **실측**(선언이 아니라)에, conformance 범위 밖 **구현체 기능**(rate-limit, auth, body-size)과 conformant 구현체 안에서의 **기능 폭 격차**를 같은 잣대로 나란히 비교한다. 예: CORS 어노테이션은 변환되지만 실측하면 7종 중 3종만 통과한다.

## 출처(1차)와 한계
- 출처: ingress-nginx 은퇴 발표(2025-11-11), "Before You Migrate"(2026-02-27), ingress2gateway 1.0(2026-03-20), IngressNightmare CVE-2025-1974, Reddit "Gateway API for Ingress-NGINX, a Maintainer's Perspective"(robertjscott).
- 한계: **중요도(상/중/하)는 directional이다.** ingress-nginx 어노테이션 사용 빈도의 공개 정량 survey가 없어, 메인테이너가 스니펫을 "가장 의존하면서 가장 위험한 기능"으로 지목한 신호와 마이그레이션 가이드의 강조를 종합했다. 검증 가능한 신호(어노테이션, i2gw 변환 커버리지, 실측)를 1차 근거로 쓴다.

엄밀성(스펙) 렌즈는 [`../conformance-view/README_ko.md`](../conformance-view/README_ko.md).
