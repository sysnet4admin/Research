# 엄밀성 뷰 (conformance)

[English](README.md)

질문: **각 구현체가 Gateway API 스펙을 얼마나 엄밀히 구현했고, 측정상 얼마나 잘 동작하나.**

공식 스펙(Support: Core/Extended × Channel: standard/experimental)에 정렬한 **라이브 실측**과, 공식 conformance가 보지 않는 **품질/비기능 지표**를 함께 본다.

## 산출물
- [`README_tables_ko.md`](README_tables_ko.md) 상세 표 (요약, 항목별, canary 품질, experimental, 벤더 매트릭스, 비기능, auth, 플레이크). GitHub에서 바로 렌더된다.
- [`report_ko.html`](report_ko.html) 같은 내용의 인터랙티브 버전. 브라우저로 열거나 raw.githack.com으로 렌더해 본다.

## 이 뷰가 공식 conformance suite와 다른 점
공식 conformance는 벤더가 자가제출하는 **이진 PASS/FAIL**이고 표준+실험 채널 기능만 본다. 이 뷰는:
- **선언이 아니라 실측**: 라이브 클러스터에서 기능을 직접 돌려 거동을 잰다.
- **품질 축 추가**: canary 80/20 분포 수렴(누적 풀링 split), 부하 성공률, 견고성 등 conformance가 측정하지 않는 지표를 본다.
- ⚠️ 공식 모델에 정렬한 **자체 데이터패스 측정**이지 upstream 스위트 등재 **공식 인증은 아니다**(공식 v1.4.0 리포트와 일치함은 1차소스로 확인).

채점 기준과 동결 절차는 프로젝트 루트의 `SCORING.md`, `rubric.yaml` 참조. 마이그레이션(출발점) 렌즈는 [`../migration-view/README_ko.md`](../migration-view/README_ko.md).
