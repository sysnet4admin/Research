#!/usr/bin/env python3
"""report.py: aggregated.json + scores.json + rubric.yaml → 두 뷰 리포트

두 뷰(같은 측정 데이터, 다른 렌즈):
  - conformance(엄밀성): 공식 Core/Extended/채널 + 실측 + 품질/비기능 + L7 기대치.
  - migration(출발점): ingress-nginx 어노테이션 앵커 + 난이도 4등급 + 구현체매트릭스 전면.

출력: metrics/conformance-view/, metrics/migration-view/ (각 report.html + README_tables.md)

사용: python3 report.py [--agg F] [--scores F] [--rubric F] [--outdir DIR]
                        [--view conformance|migration|both]
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path

import gwlib

HERE = Path(__file__).resolve().parent
GW = HERE.parent

STATE_MARK = {"pass": "PASS", "flaky": "FLAKY", "unsupported": "n/a",
              "no-data": "-", "fail": "FAIL", "not-configured": "미구성"}
CANARY_TEST = "canary-traffic"

# auth(JWT, ext-authz)는 per-round 자동측정 미통합(E8, E9 라이브 검증값, 비채점 stub).
# 두 뷰가 공유하는 단일 출처. (JWT, ext-authz 구현체, ext-authz 표준 GEP-1494 필터)
AUTH = {
    "nginx":    ("Plus전용(OSS는 Basic만)", "SnippetsFilter 저수준",  "미구현(404)"),
    "envoy":    ("native JWKS",             "SecurityPolicy native",   "미구현(UnsupportedValue)"),
    "istio":    ("native JWKS",             "AuthzPolicy CUSTOM(mesh)", "미구현(InvalidFilter)"),
    "cilium":   ("미지원",                  "미지원",                  "표준필터 미구현(통과)★"),
    "kong":     ("KGO 시크릿이슈(거부만)",  "OSS 미지원",              "미구현(404)"),
    "traefik":  ("미지원",                  "forwardAuth native",      "수용하나 500"),
    "kgateway": ("native JWKS",             "GatewayExtension native", "표준필터 미구현(통과)★"),
}


def _canary_cell(ta: dict | None) -> str:
    """canary 셀: 다른 행과 동일하게 PASS/FAIL만. 세부 split 비율은 윗첨자 2b로 연결."""
    pool = (ta or {}).get("canary_pool")
    if not pool or pool.get("v1_ratio") is None:
        return "-"
    return "PASS" if pool.get("within_2sigma") else "FAIL"


def _detail_state(test_agg: dict | None) -> str:
    if test_agg is None or test_agg.get("valid_rounds", 0) == 0:
        # 데이터 없음 중에서도 하네스 미구성(not-configured)은 구분(설계상 미지원 아님).
        if test_agg and (test_agg.get("counts") or {}).get("not-configured", 0) > 0:
            return "not-configured"
        return "no-data"
    pr = test_agg["pass_rate"]
    if pr is None:
        return "no-data"
    if pr >= 1.0:
        return "pass"
    if pr <= 0.0:
        # 측정상 실패(매 라운드 fail)와 설계상 미지원(unsupported skip)을 구분.
        if (test_agg.get("counts") or {}).get(gwlib.RESULT_FAIL, 0) > 0:
            return "fail"
        return "unsupported"
    return "flaky"


# ===========================================================================
# 엄밀성 뷰 (conformance)
# ===========================================================================
def build_conformance_markdown(agg: dict, scores: dict, rubric: dict) -> str:
    groups = gwlib.level_groups(rubric)
    impls = list(scores["implementations"].keys())
    L = []
    cs = agg.get("canary_source") or {}
    canary_rounds = cs.get("rounds_sampled")
    basis = f"결정론 {scores.get('rounds')} rounds"
    if canary_rounds:
        basis += f", canary {canary_rounds}라운드 풀"
    L.append(f"# Gateway API PoC 엄밀성 뷰 (Gateway API {scores.get('gateway_api_version')}, "
             f"{basis})\n")
    L.append(f"> **라운드 근거**: 결정론(determinstic) 항목은 v3 캠페인 {scores.get('rounds')}라운드, "
             f"canary(가중 라우팅)는 동결된 {canary_rounds or '155'}라운드 풀이다(발표 메트릭 동결). "
             "두 축의 라운드 수가 다르며, 섹션 2의 canary 행 판정은 155라운드 풀링(섹션 3)에 근거한다.\n")
    L.append("> 공식 스펙(Core/Extended/채널)에 정렬한 **실측 검증** + conformance가 보지 않는 "
             "**품질/비기능 지표**(canary 분포, 부하, 견고성). 출발점(마이그레이션) 뷰는 "
             "`../migration-view/` 참조.\n")

    # 1. 요약
    n_core = len(groups["core"])
    n_ext = len(groups["extended-standard"])
    n_xe = len(groups["extended-experimental"])
    L.append("## 1. 요약 (conformance)\n")
    L.append(f"> 공식 Gateway API conformance는 **채널별**로 채점된다(Core+Extended). 우리는 "
             f"**experimental 채널 CRD**(standard 상위집합)로 측정하므로 두 채널 모두 본다.\n")
    L.append(f"> 채점 = **Core {n_core}**(필수, Support:Core) + **Extended(standard) {n_ext}**(안정) "
             f"+ **Extended(experimental) {n_xe}**(필드 변경 가능). "
             f"experimental 필드(conformance 기능 없음), 구현체, 비기능은 비채점(섹션 5~8).\n")
    L.append(f"| 구현체 | 버전 | Core ({n_core}) | Extended-std ({n_ext}) | Extended-exp ({n_xe}) | 미통과 Core |")
    L.append("|---|---|---|---|---|---|")
    for i in impls:
        s = scores["implementations"][i]
        eb = s["extended_breadth"]
        xe = s.get("extended_experimental_breadth", {"supported": 0, "total": n_xe})
        core_pass = n_core - len(s["core_failed"])
        conf = (f"{core_pass}/{n_core} 통과" if s["core_conformant"]
                else f"{core_pass}/{n_core} (미달)")
        failed = ", ".join(s["core_failed"]) or "-"
        L.append(f"| {i} | {s.get('version') or '-'} | {conf} | "
                 f"{eb['supported']}/{eb['total']} | {xe['supported']}/{xe['total']} | {failed} |")
    L.append("")
    L.append("> **Core N/7 통과**: Support:Core 필수 기능. 전부 통과 = 공식 모델의 \"conformant\". "
             "선택(Extended) 미지원은 적합성에 무영향.")
    L.append("> **Extended는 채널 2축**: `std`=standard 채널(안정), `exp`=experimental 채널(필드 변경 가능). "
             "둘 다 공식 conformance의 Extended 기능이며 채널만 다르다(GEP-1709: conformance는 채널별 채점). "
             f"v1.4 experimental Extended는 적어 exp 축은 {n_xe}항목(CORS 등).")
    L.append("> ⚠️ 이 표는 **공식 모델에 정렬된 자체 데이터패스 측정**이지 upstream 스위트 등재 **공식 인증은 아님** "
             "(공식 v1.4.0 리포트와 일치함은 1차소스로 확인).\n")
    L.append("> **버전 주의(스냅샷)**: 측정 시점 버전 기준이며, 이후 릴리스에서 일부 미지원이 해소됐다 "
             "(2026-06-10 공식 conformance/CHANGELOG로 확인). Traefik backend-request-header-mod는 "
             "**3.7에서 지원**(측정 3.6.17), kgateway backend-tls는 **2.3.0에서 지원**(측정 2.2.2), "
             "Cilium backend-tls/ExternalAuth는 **1.20에서 지원**(측정 1.19.4, 1.20 GA 임박), "
             "Kong TLSRoute는 **KGO 2.2.0에서 지원**(측정 2.1.x). 인용 시 측정 버전을 함께 밝힌다.\n")

    # 2. 항목별 상세 (채점: Core + Extended 양 채널)
    graded = groups["core"] + groups["extended-standard"] + groups["extended-experimental"]
    L.append(f"## 2. 항목별 상세 (채점 {n_core + n_ext + n_xe}: Core {n_core} + Extended-std {n_ext} + Extended-exp {n_xe})\n")
    L.append("| 테스트 | 구분 | " + " | ".join(impls) + " |")
    L.append("|" + "---|" * (2 + len(impls)))
    lv_label = {"core": "Core(필수)", "extended-standard": "Extended-std",
                "extended-experimental": "Extended-exp"}
    for t in graded:
        meta = rubric["tests"][t]
        lv = lv_label.get(meta["level"], meta["level"])
        diff = meta.get("differentiation")
        dmark = {"common": " ◇공통", "differentiating": " ◆차별"}.get(diff, "")
        cells = []
        for i in impls:
            ta = agg["implementations"].get(i, {}).get("tests", {}).get(t)
            if t == CANARY_TEST:
                cells.append(_canary_cell(ta))
            else:
                cells.append(STATE_MARK[_detail_state(ta)])
        label = f"[{t}](#canary-detail)" if t == CANARY_TEST else t
        L.append(f"| {label}{dmark} | {lv} | " + " | ".join(cells) + " |")
    L.append("")
    L.append("> canary는 표본 테스트라 누적 풀링 split(2σ)으로 PASS/FAIL 판정한다. "
             "**행 이름 `canary-traffic`을 누르면** 구현체별 세부 split 비율(섹션 3)로 이동한다.")
    L.append("> ◇공통=7종 전부 지원(마이그레이션 안전 보증), ◆차별=구현체별 갈림. "
             "v1.4 standard 채널 conformance flag 보유 항목만 graded.\n")

    # 3. canary 품질 지표
    L.append('<a id="canary-detail"></a>')
    L.append("## 3. canary 품질 지표 (가중 라우팅 80/20, 풀링)\n")
    L.append("| 구현체 | 누적 split(v1%) | 표본수 | 라운드 평균 v1 | min~max | 2σ이탈 라운드 |")
    L.append("|---|---|---|---|---|---|")
    for i in impls:
        ta = agg["implementations"].get(i, {}).get("tests", {}).get(CANARY_TEST, {})
        p = (ta or {}).get("canary_pool")
        if not p or p.get("v1_ratio") is None:
            L.append(f"| {i} | - | - | - | - | - |")
            continue
        L.append(f"| {i} | {p['v1_ratio']*100:.1f}% | {p['samples']} | "
                 f"{p['per_round_v1_mean']} | {p['per_round_v1_min']}~{p['per_round_v1_max']} | "
                 f"{p['per_round_excursions']}/{p['rounds_sampled']} |")
    L.append("")
    if cs.get("note"):
        L.append(f"> **출처**: {cs['note']}")
    L.append("> **누적 split(v1%)**: 전 라운드 v1/v2 요청을 합산한 실제 분배 비율(목표 80%). "
             "이게 목표에 2σ 내로 수렴하면 canary PASS.")
    L.append("> **2σ이탈 라운드**: 라운드마다 50요청 중 v1 횟수가 통계적 2σ 구간 **[35,45]**(목표 40±2σ, "
             "sigma=2.83이라 정수 구간 35~45)을 벗어난 라운드 수 / 전체. 예 `5/155` = 155라운드 중 5라운드가 구간 밖. "
             "표본 노이즈상 약 5%/라운드는 정상 이탈이라 **실패가 아니라 분포 품질 참고치**다"
             "(그래서 판정은 라운드별이 아닌 누적 풀링으로 한다).\n")

    # 4. experimental 필드
    exp = [t for t in groups["experimental"] if not t.startswith("auth")]
    L.append("## 4. experimental 필드 (conformance 기능 없음, 채점 불가, 역량 보고)\n")
    L.append("> API에 experimental **필드**로 존재하나 v1.4 conformance **기능(테스트) 자체가 없다**"
             "(CORS 같은 experimental Extended와 다름 → 그건 섹션 2에 채점됨).\n")
    L.append("| 구현체 | " + " | ".join(exp) + " |")
    L.append("|" + "---|" * (1 + len(exp)))
    for i in impls:
        s = scores["implementations"][i]["experimental"]
        cells = [STATE_MARK.get(s.get(t, "no-data"), "-") for t in exp]
        L.append(f"| {i} | " + " | ".join(cells) + " |")
    L.append("")
    # retry 상세(HTTPRoute 표준 retry 필드. 1 요청당 업스트림 시도 수, rounds-ops 캠페인)
    rt = []
    for i in impls:
        st = scores["implementations"][i]["experimental"].get("retry")
        ta = agg["implementations"].get(i, {}).get("tests", {}).get("retry") or {}
        att = (ta.get("sample_metadata") or {}).get("upstream_attempts")
        infra = (ta.get("counts") or {}).get("infra-excluded", 0)
        if st == "pass":
            v = f"{i} {att}회 시도" if att else f"{i} 지원"
            if infra:
                v += "(일부 라운드 라우팅 실패)"
            rt.append(v)
        elif st in ("unsupported", "fail"):
            rt.append(f"{i} 미적용")
    if rt:
        L.append("> **retry 상세**(HTTPRoute 표준 retry 필드 `retry.attempts:3,codes:[503]`, "
                 "503에 1 요청당 업스트림 시도 수): " + ", ".join(rt)
                 + ". 시도 수 차이는 구현체 retry 정책(istio/kgateway가 더 공격적). "
                 "'(일부 라운드 라우팅 실패)'는 해당 구현체가 일부 라운드에서 라우트 프로그래밍에 "
                 "실패해 그 라운드를 분모에서 제외했다는 뜻.\n")

    # 매트릭스 셀 렌더 헬퍼
    def _matrix_cells(item_list):
        rows = []
        for i in impls:
            m = scores["implementations"][i]["impl_matrix"]
            cells = []
            for t in item_list:
                entry = m.get(t, {})
                mv = entry.get("matrix") or {}
                label = mv.get("matrix_value") or STATE_MARK.get(entry.get("state"), "-")
                ta = agg["implementations"].get(i, {}).get("tests", {}).get(t)
                pr = (ta or {}).get("pass_rate")
                if t == "config-robustness" and pr is not None:
                    vr = (ta or {}).get("valid_rounds", 0)
                    if pr >= 1.0:
                        label = "robust"
                    elif pr <= 0.0:
                        label = "fragile"
                    else:
                        nfail = round((1 - pr) * vr)
                        label = f"robust {pr*100:.1f}% ({nfail}/{vr} fragile)"
                cells.append(str(label))
            rows.append(f"| {i} | " + " | ".join(cells) + " |")
        return rows

    # 5. 구현체 기능 매트릭스
    vendor_items = [t for t in groups["impl-specific"]
                    if not t.startswith("auth") and t != "health-check"]
    L.append("## 5. 구현체 기능 매트릭스 (Gateway API 표준 외, conformance 무관)\n")
    L.append("> 표준에 없고 구현체 고유 메커니즘으로 제공. native / low-level-config / unsupported로 비교.\n")
    L.append("| 구현체 | " + " | ".join(vendor_items) + " |")
    L.append("|" + "---|" * (1 + len(vendor_items)))
    L += _matrix_cells(vendor_items)
    L.append("")
    L.append("> **측정 설정 주의(공정성, 2026-06-10 재검증)**: 일부 항목은 구현체 권장 설정을 켜야 "
             "동작한다. Kong은 query-param/method 매칭을 위해 `router_flavor=expressions`로 측정했다"
             "(OSS 디폴트 traditional_compatible은 query-param 미지원, 즉 디폴트로 재면 더 낮게 나온다). "
             "kgateway basic-auth는 TrafficPolicy basicAuth로 동작(native). Cilium rate-limiting/body-size는 "
             "선언형 표준/벤더 경로가 없어 unsupported로 적었으나, raw CiliumEnvoyConfig(istio EnvoyFilter와 "
             "동급 저수준 escape hatch)로는 가능하다(미측정). Istio tls-passthrough는 alpha 플래그"
             "(PILOT_ENABLE_ALPHA_GATEWAY_API)를 켜도 v1.4에서 미동작이라 미지원(istio TLSRoute는 Terminate만 "
             "공식 conformant, passthrough 미검증, 이슈 #47366).\n")

    # 6. 비기능 / 운영 지표
    nonfunc_items = (["health-check"] if "health-check" in groups["impl-specific"] else []) \
        + groups["non-functional"]
    L.append("## 6. 비기능 / 운영 지표 (기능 아님, 성능, 견고성, 복구)\n")
    L.append("| 구현체 | " + " | ".join(nonfunc_items) + " |")
    L.append("|" + "---|" * (1 + len(nonfunc_items)))
    L += _matrix_cells(nonfunc_items)
    L.append("")
    # failover-recovery 복구 상세(매트릭스 셀은 PASS/n-a, 시간은 여기 주석으로)
    fo = []
    for i in impls:
        st = scores["implementations"][i]["impl_matrix"].get("failover-recovery", {}).get("state")
        ta = agg["implementations"].get(i, {}).get("tests", {}).get("failover-recovery") or {}
        meta = ta.get("sample_metadata") or {}
        rs = meta.get("recovery_s")
        if st == "pass" and rs is not None:
            fo.append(f"{i} {'무중단' if rs == 0 else f'복구~{rs}s'}")
        elif st == "unsupported":
            fo.append(f"{i} 측정제외(공유 eBPF)")
    if fo:
        L.append("> **failover-recovery 상세**(데이터플레인 강제 재시작 후 복구, rounds-ops 별도 캠페인): "
                 + ", ".join(fo) + ". 무중단=파드 교체 중 트래픽 무손실(outage 0), "
                 "복구~Ns=약 N초 공백 후 정상화. 모두 파드 교체(pod_changed)로 교란 확인됨.\n")
    # health-check 상세(능동 health check가 unhealthy 백엔드를 푸는가)
    hc = []
    for i in impls:
        st = scores["implementations"][i]["impl_matrix"].get("health-check", {}).get("state")
        if st == "pass":
            hc.append(f"{i} 지원")
        elif st == "unsupported":
            hc.append(f"{i} 미지원")
    if hc:
        L.append("> **health-check 상세**(능동 health check가 unhealthy 백엔드를 풀에서 빼는가. "
                 "good 2 + bad 1(/health 503) 백엔드, bad 완전 제거 시 지원, rounds-ops): "
                 + ", ".join(hc) + ". 지원=envoy BackendTrafficPolicy / kong KongUpstreamPolicy / "
                 "kgateway BackendConfigPolicy의 능동 probe. 미지원=능동 HC 미노출"
                 "(nginx는 Plus 전용, istio는 mesh outlier, cilium/traefik 미노출).\n")
    # config-robustness 측정 조건/뉘앙스(공개값은 표준 설정 기준임을 명시)
    if any("config-robustness" in scores["implementations"][i].get("impl_matrix", {}) for i in impls):
        L.append("> **config-robustness 측정 조건**: '모든 기능을 동시에 배포했을 때 기본 라우팅이 "
                 "살아남는가'. 위 값은 표준 기능셋(결정론 캠페인) 기준이다. kong은 config-load에 "
                 "민감해, 운영 테스트 정책까지 동시에 얹은 더 무거운 설정(rounds-ops 캠페인)에선 같은 "
                 "항목이 fragile로 떨어진다. kong의 all-or-nothing 설정 모델 특성과 일치하며, 위 robust "
                 "표기는 표준 설정 시나리오 한정이다.\n")

    # 7. auth
    L.append("## 7. auth (주제: 구현체/실험 혼재, 마이그레이션 핵심)\n")
    L.append("> 카테고리가 아니라 **주제 단면**: auth는 분류상 흩어져 있다. **JWT=구현체(섹션 5형, 표준 없음)**, "
             "**ext-authz 표준필터=experimental(GEP-1494)**, **ext-authz 구현체=구현체**. ingress-nginx auth-url "
             "마이그레이션 핵심이라 한 곳에 모음. 7종 라이브 검증값(E8, E9), per-round 자동측정 미통합(비채점).\n")
    L.append("| 구현체 | JWT | ext-authz(구현체) | ext-authz(표준 GEP-1494 필터) |")
    L.append("|---|---|---|---|")
    for i in impls:
        a = AUTH.get(i, ("-", "-", "-"))
        L.append(f"| {i} | {a[0]} | {a[1]} | {a[2]} |")
    L.append("")
    L.append("> ★ GEP-1494 표준 ExternalAuth 필터는 어떤 구현체도 강제하지 못한다. "
             "envoy/nginx/istio/kong/traefik은 거부 또는 오류, cilium/kgateway는 표준 필터를 "
             "구현하지 않아 무인증 트래픽이 그대로 통과한다(silent no-op). GEP-1494는 experimental "
             "단계라 실패모드(fail-open/closed)를 규정하지 않는다(스펙에 'MUST fail closed' 문구 없음, "
             "PR #4001에서 실패 의미 보류). cilium은 1.20, kgateway는 벤더 TrafficPolicy로만 ext-authz를 "
             "제공한다. 결론: 표준 필터는 아직 프로덕션 auth로 못 쓰고 벤더 CRD가 필요하다.\n")

    # 8. 플레이크
    flaky = {i: [t for t in s["flaky_tests"] if t != CANARY_TEST]
             for i, s in scores["implementations"].items()
             if [t for t in s.get("flaky_tests", []) if t != CANARY_TEST]}
    L.append("## 8. 플레이크 / 데이터 주의 (canary 제외, 섹션 3 참조)\n")
    if flaky:
        for i, ts in flaky.items():
            parts = []
            for t in ts:
                ta = agg["implementations"].get(i, {}).get("tests", {}).get(t, {})
                pr = ta.get("pass_rate")
                parts.append(f"{t}({pr*100:.1f}%)" if pr is not None else t)
            L.append(f"- {i}: {', '.join(parts)} (통과율 0<p<1, 비채점 매트릭스)")
    else:
        L.append("- (현재 비-canary 플레이크 없음)")
    L.append("")

    # 9. not-configured(하네스 미구성 = 계측 공백, 설계상 미지원과 구분)
    notcfg = {i: list(s.get("data_errors", {}).keys())
              for i, s in scores["implementations"].items() if s.get("data_errors")}
    if notcfg:
        L.append("## 9. 데이터 주의: not-configured (자동 라운드 미통합)\n")
        L.append("> 자동 라운드 루프에 통합되지 않아 round 데이터가 없는 항목. 두 종류로 갈린다. "
                 "(a) **auth-jwt/auth-extauth는 측정 완료**다. 라이브 검증(E8/E9)했고 값은 7절 auth 표에 "
                 "있다. 자동 루프 통합만 보류라 round에는 `미구성`으로 찍힐 뿐 데이터가 없는 게 아니다. "
                 "(b) **그 외는 미측정**(라이브 로직 부재, 재측정 대상). 모두 비채점이라 등급 무관.\n")
        for i, ts in notcfg.items():
            auth = sorted(t for t in ts if t.startswith("auth"))
            gap = sorted(t for t in ts if not t.startswith("auth"))
            parts = []
            if auth:
                parts.append(f"측정완료(E8/E9, 7절 참조): {', '.join(auth)}")
            if gap:
                parts.append(f"미측정: {', '.join(gap)}")
            L.append(f"- {i}: " + " | ".join(parts))
        L.append("")

    return "\n".join(L)


# ===========================================================================
# 출발점 뷰 (migration)
# ===========================================================================
_TIER_ORDER = ["standard", "caution", "vendor", "blocked"]
_TIER_SHORT = {"standard": "표준", "caution": "주의", "vendor": "구현체", "blocked": "불가"}
_IMPORTANCE = {"high": "상", "medium": "중", "low": "하"}
_I2GW = {"converts": "✓", "partial": "~", "no": "✗", "n-a": "native"}
# 커버리지 요약에서 "지원(동작)"으로 셀 수 있는 auth 텍스트 (저수준 포함)
_AUTH_COVERED = {
    "native JWKS": True, "Plus전용(OSS는 Basic만)": False, "KGO 시크릿이슈(거부만)": False,
    "SecurityPolicy native": True, "AuthzPolicy CUSTOM(mesh)": True, "forwardAuth native": True,
    "GatewayExtension native": True, "SnippetsFilter 저수준": True, "OSS 미지원": False, "미지원": False,
}


def _mig_cell(agg: dict, scores: dict, impl: str, t: str | None) -> str:
    """출발점 점검표의 구현체별 셀. maps_to에 따라 실측/매트릭스/auth/구조 분기."""
    if t is None:
        return "(미측정)"
    if t == "auth-jwt":
        return AUTH.get(impl, ("-",))[0]
    if t == "auth-extauth":
        return AUTH.get(impl, ("-", "-"))[1]
    if t == CANARY_TEST:
        ta = agg["implementations"].get(impl, {}).get("tests", {}).get(t)
        return _canary_cell(ta)
    s = scores["implementations"][impl]
    if t in s.get("impl_matrix", {}):
        entry = s["impl_matrix"][t]
        mv = entry.get("matrix") or {}
        return mv.get("matrix_value") or STATE_MARK.get(entry.get("state"), "-")
    if t in s.get("experimental", {}):
        return STATE_MARK.get(s["experimental"][t], "-")
    ta = agg["implementations"].get(impl, {}).get("tests", {}).get(t)
    return STATE_MARK[_detail_state(ta)]


def _mig_covered(cell: str) -> bool:
    """커버리지 요약용: 셀이 '동작(저수준 포함)'이면 True. 품질차는 상세표가 보여줌."""
    if cell == "PASS":
        return True
    if cell in ("FAIL", "n/a", "-", "(미측정)", "no-data", "unsupported", "overmatch", "미구성"):
        return False
    if cell in ("native", "low-level-config", "supported", "robust"):
        return True
    return _AUTH_COVERED.get(cell, False)


def build_migration_markdown(agg: dict, scores: dict, rubric: dict) -> str:
    mv = rubric["migration_view"]
    caps = mv["capabilities"]
    tiers = mv["tiers"]
    impls = list(scores["implementations"].keys())
    L = []
    gwv = mv['meta']['gateway_api_version']
    L.append(f"# Gateway API PoC 출발점 뷰 (ingress-nginx → Gateway API {gwv} 마이그레이션)\n")
    L.append(f"> **{mv['meta']['headline']}**\n")
    L.append("> **이 뷰의 차별점**: 공식 conformance(선언 PASS/FAIL), ingress2gateway(기계 변환 여부)와 달리, "
             "라이브 클러스터 **실측** + conformance 범위 밖 **구현체 기능**(rate-limit, auth, body-size) + "
             "conformant 내부의 **기능폭 격차**를 한 잣대로 가로비교한다. 엄밀성(스펙) 뷰는 "
             "`../conformance-view/` 참조.\n")
    L.append(f"> **측정 기준: Gateway API {gwv}** (2026-06 측정 시점, ingress2gateway {mv['meta']['i2gw_version']}). "
             "난이도 등급은 이 버전 기준이다. **v1.5(2026-04-21 릴리스) 신규 기능**(mTLS 클라이언트 등)은 "
             "v1.4 측정 범위 밖이라 `TBD(v1.5)`로 표기하고 차기 재베이스라인 대상이다"
             "(재베이스라인은 Cilium 1.20 stable, 7월 말 예정 이후). "
             "반면 **CORS, 외부 인증, TLSRoute는 v1.4 experimental 채널에서 이미 7종 실측**했으며, "
             "v1.5에서 표준 채널로 승격되면 🟡→🟢으로 올라갈 수 있다. "
             "셀 값 출처는 엄밀성 뷰의 실측과 동일(같은 측정 데이터).\n")

    # 1. 난이도 4등급
    L.append("## 1. 마이그레이션 난이도 4등급\n")
    L.append("| 등급 | 의미 |")
    L.append("|---|---|")
    for k in _TIER_ORDER:
        L.append(f"| **{tiers[k]['name']}** | {tiers[k]['desc']} |")
    L.append("")

    # 2. 구현체별 커버리지
    L.append("## 2. 구현체별 커버리지 (측정 가능 항목 기준)\n")
    L.append("> *\"내 ingress-nginx를 이 구현체로 옮기면 등급별로 몇 개가 실제 동작하나.\"* "
             "구현체별로 실제 측정한 항목만 센다. 🔴 마이그레이션 불가 등급과, 구현체와 무관하게 "
             "Gateway API 스펙 수준에서만 판정한 항목(표에서 `(미측정)`), 그리고 측정 매핑이 없는 "
             "구조적 행(예: mTLS 클라이언트=`TBD(v1.5)`)은 제외한다. 그래서 등급별 분모가 3절 "
             "점검표의 행 수보다 작을 수 있다(예: 🟡은 점검표 8행 중 mTLS를 뺀 7개 기준).\n")
    measurable = {k: [c for c in caps if c["tier"] == k and c["maps_to"]] for k in _TIER_ORDER}
    head = ["구현체"] + [f"{tiers[k]['name'].split(' ')[0]} {_TIER_SHORT.get(k, k)}({len(measurable[k])})"
                         for k in _TIER_ORDER if measurable[k]] + ["합계"]
    L.append("| " + " | ".join(head) + " |")
    L.append("|" + "---|" * len(head))
    for i in impls:
        cells = []
        tot_ok = tot_n = 0
        for k in _TIER_ORDER:
            if not measurable[k]:
                continue
            ok = sum(_mig_covered(_mig_cell(agg, scores, i, c["maps_to"])) for c in measurable[k])
            n = len(measurable[k])
            cells.append(f"{ok}/{n}")
            tot_ok += ok
            tot_n += n
        L.append(f"| {i} | " + " | ".join(cells) + f" | **{tot_ok}/{tot_n}** |")
    L.append("")
    L.append("> 지원 = **동작**(low-level-config/snippet 저수준 포함). 동작 여부만 세고 품질차(native vs 저수준)는 "
             "3절 상세표가 보여준다. 외부 auth는 구현체 native 기준(GEP-1494 표준 필터는 아무도 강제 못 함, "
             "엄밀성 뷰 7절).\n")

    # 3. 마이그레이션 점검표 (난이도 그룹)
    L.append(f"## 3. 마이그레이션 점검표 ({len(caps)}개, 난이도 그룹)\n")
    L.append(f"> **범례: i2gw 변환**(ingress2gateway {mv['meta']['i2gw_version']}을 어노테이션별로 **직접 실행한 실측**, "
             "before/after manifest는 `migration/i2gw/`): "
             "`✓` 자동변환 / `~` 부분/best-effort(또는 일부 어노테이션 거절) / `✗` 미변환(수동 재설계) / "
             "`native` Ingress 기본기능이라 변환 대상 아님(가장 쉬움). "
             "**변환됨 ≠ 동작함**. 구현체 셀(PASS/native 등)이 실제 지원을 보여준다.\n")
    tier_counts = {k: sum(1 for c in caps if c["tier"] == k) for k in _TIER_ORDER}
    for k in _TIER_ORDER:
        group = [c for c in caps if c["tier"] == k]
        L.append(f"### {tiers[k]['name']} ({tier_counts[k]})\n")
        L.append("| 기능 | ingress-nginx 어노테이션 | 중요도 | GW API v1.4 | i2gw | "
                 + " | ".join(impls) + " |")
        L.append("|" + "---|" * (5 + len(impls)))
        notes = []
        for idx, c in enumerate(group, 1):
            cells = [_mig_cell(agg, scores, i, c["maps_to"]) for i in impls]
            # 구조적 행(maps_to 없음)의 셀 표식 오버라이드(예: mtls-client = TBD(v1.5))
            if c["maps_to"] is None and c.get("structural_cell"):
                cells = [c["structural_cell"]] * len(impls)
            imp = _IMPORTANCE.get(c["importance"], c["importance"])
            i2 = _I2GW.get(c["i2gw"], c["i2gw"])
            nref = ""
            if c.get("note"):
                notes.append(f"  - **{c['capability']}**: {c['note']}")
                nref = " ※"
            L.append(f"| {c['capability']}{nref} | `{c['annotation']}` | {imp} | "
                     f"{c['gw_status']} | {i2} | " + " | ".join(cells) + " |")
        L.append("")
        if notes:
            L.append("> ※ 함정/주석:")
            L += notes
            L.append("")

    # 4. 차별점, 출처, 한계
    L.append("## 4. 읽는 법 / 출처 / 한계\n")
    L.append("- **셀 읽기**: 🟢🟡 등급은 실측 `PASS/FAIL/n/a`. 🟠 구현체는 `native/low-level-config/unsupported` "
             "매트릭스. auth는 라이브 검증값(엄밀성 7절). `(미측정)`은 구현체별로 측정하지 않고 "
             "Gateway API 스펙 수준에서만 판정한 항목(예: snippet은 어느 구현체든 등가물이 없음).")
    L.append(f"- **i2gw 변환**: ingress2gateway {mv['meta']['i2gw_version']}을 어노테이션별 샘플 Ingress로 **직접 실행**해 "
             "변환 결과/경고를 기록한 **실측값**(연구 추정 아님). before/after manifest + 로그 + 분류 근거는 "
             "`migration/i2gw/`(ingress/, gateway/, logs/, results.json). `✓`=자동변환, `~`=부분/일부 거절, "
             "`✗`=미변환(수동 재설계), `native`=Ingress 기본기능이라 변환 대상 아님.")
    L.append("- **점검표에서 제외한 것**: method 매칭, query-param 매칭처럼 ingress-nginx에 없던 Gateway API "
             "신규 표준 기능은 이 점검표에 넣지 않았다. 마이그레이션으로 \"넘어갈 것\"이 아니라 옮긴 뒤 "
             "추가로 얻는 기능이기 때문이다(엄밀성 뷰에서 측정).")
    L.append("- **중요도(상/중/하)**: ingress-nginx 실사용 중요도. directional이다. 공개 정량 survey가 없어, "
             "메인테이너가 snippet을 \"가장 의존+가장 위험\"으로 지목한 신호와 마이그레이션 가이드 강조를 종합했다.")
    L.append("- **출처(1차)**: ingress-nginx 은퇴 발표(2025-11-11), \"Before You Migrate\"(2026-02-27), "
             "ingress2gateway 1.0(2026-03-20), IngressNightmare CVE-2025-1974, "
             "Reddit \"Gateway API for Ingress-NGINX, a Maintainer's Perspective\".")
    L.append("- **한계**: 🟡 다수(CORS, 외부 인증, mTLS 클라이언트, TLSRoute)는 v1.4 실험채널이며 v1.5에서 Standard 승격 "
             "예정 → 시점에 따라 등급 상향 가능. 🔴 snippet은 설계상 영구 미지원(재설계 필수).\n")
    return "\n".join(L)


# ===========================================================================
# HTML 래퍼 (뷰 공용)
# ===========================================================================
_CSS = ("body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;"
        "margin:2rem auto;max-width:1280px;padding:0 1rem;color:#1a1a1a;line-height:1.5;}"
        "h1{border-bottom:2px solid #333;padding-bottom:.3rem;}"
        "h2{margin-top:2rem;border-bottom:1px solid #ddd;padding-bottom:.2rem;}"
        "h3{margin-top:1.5rem;color:#222;}"
        "table{border-collapse:collapse;margin:.6rem 0;font-size:.86rem;}"
        "td,th{border:1px solid #ccc;padding:.32rem .6rem;text-align:left;vertical-align:top;}"
        "th{background:#f2f4f7;white-space:nowrap;}tr:nth-child(even) td{background:#fafbfc;}"
        ".ok{color:#137333;font-weight:600;}.bad{color:#b00020;font-weight:700;}"
        ".muted{color:#9aa0a6;}.warn{color:#b06000;}.tbd{color:#5b6cc4;font-style:italic;}"
        "blockquote{margin:.5rem 0;padding:.4rem .9rem;border-left:3px solid #cdd2d8;"
        "background:#f7f8fa;color:#444;font-size:.9rem;}"
        "code{background:#eef0f2;padding:.05rem .3rem;border-radius:3px;font-size:.85em;}"
        "a{color:#1a56c4;}")

import html as _htmllib
import re as _re

_CELL_CLASS = {
    "PASS": "ok", "native": "ok", "supported": "ok", "robust": "ok",
    "FAIL": "bad", "FLAKY": "warn", "미구성": "warn",
    "n/a": "muted", "unsupported": "muted", "미지원": "muted", "-": "muted",
    "(미측정)": "muted", "no-data": "muted", "overmatch": "warn", "low-level-config": "warn",
    # i2gw 변환 컬럼 기호 색상: 된다=녹색, 부분=주황, 안됨=빨강
    "✓": "ok", "~": "warn", "✗": "bad",
    # v1.5 신규(차기 측정) 표식
    "TBD(v1.5)": "tbd",
}


def _link_sub(m) -> str:
    text, url = m.group(1), m.group(2)
    # scheme allowlist: http(s)/앵커/상대경로만 href로. javascript:, data: 등은 텍스트로.
    if not _re.match(r"(https?:|#|/|\.\.?/)", url):
        return _htmllib.escape(f"[{text}]({url})", quote=False)
    return f'<a href="{_htmllib.escape(url, quote=True)}">{text}</a>'


def _inline(s: str) -> str:
    s = _htmllib.escape(s, quote=False)
    s = _re.sub(r"\[([^\]]+)\]\(([^)]+)\)", _link_sub, s)
    s = _re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    s = _re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    return s


def _cell(text: str, header: bool) -> str:
    t = text.strip()
    tag = "th" if header else "td"
    cls = None if header else _CELL_CLASS.get(t)
    attr = f' class="{cls}"' if cls else ""
    return f"<{tag}{attr}>{_inline(t)}</{tag}>"


def _is_sep_row(line: str) -> bool:
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    return bool(cells) and all(_re.fullmatch(r":?-+:?", c) for c in cells if c != "")


def _md_to_html(md: str) -> str:
    out, i = [], 0
    lines = md.split("\n")
    n = len(lines)
    while i < n:
        ln = lines[i]
        s = ln.strip()
        if not s:
            i += 1
            continue
        if _re.fullmatch(r'<a id="[^"]+"></a>', s):     # 앵커 통과
            out.append(ln)
            i += 1
            continue
        m = _re.match(r"(#{1,4})\s+(.*)", s)
        if m:
            lvl = len(m.group(1))
            out.append(f"<h{lvl}>{_inline(m.group(2))}</h{lvl}>")
            i += 1
            continue
        if s.startswith("|"):                            # 테이블 블록
            block = []
            while i < n and lines[i].strip().startswith("|"):
                block.append(lines[i].strip())
                i += 1
            rows = [r for r in block if not _is_sep_row(r)]
            out.append("<table>")
            for ri, row in enumerate(rows):
                cells = [c for c in row.strip().strip("|").split("|")]
                header = (ri == 0)
                out.append("<tr>" + "".join(_cell(c, header) for c in cells) + "</tr>")
            out.append("</table>")
            continue
        if s.startswith(">"):                            # 인용 블록(연속 병합)
            buf = []
            while i < n and lines[i].strip().startswith(">"):
                buf.append(lines[i].strip()[1:].strip())
                i += 1
            out.append("<blockquote>" + "<br>".join(_inline(b) for b in buf) + "</blockquote>")
            continue
        if _re.match(r"-\s+", s):                         # 리스트(연속 병합)
            buf = []
            while i < n and _re.match(r"-\s+", lines[i].strip()):
                buf.append(lines[i].strip()[1:].strip())
                i += 1
            out.append("<ul>" + "".join(f"<li>{_inline(b)}</li>" for b in buf) + "</ul>")
            continue
        out.append(f"<p>{_inline(s)}</p>")               # 일반 문단
        i += 1
    return "\n".join(out)


def _conformance_summary_html(scores: dict) -> str:
    rows = ["<table><tr><th>구현체</th><th>Core(필수)</th>"
            "<th>Extended(선택)</th><th>미통과 Core</th></tr>"]
    for i, s in scores["implementations"].items():
        eb = s["extended_breadth"]
        n_core = s.get("core_total", 7)
        core_pass = s.get("core_passed", n_core - len(s["core_failed"]))
        conf = f"{core_pass}/{n_core} 통과" if s["core_conformant"] else f"{core_pass}/{n_core} (미달)"
        cls = "ok" if s["core_conformant"] else "bad"
        rows.append(f"<tr><td>{i}</td><td class='{cls}'>{conf}</td>"
                    f"<td>{eb['supported']}/{eb['total']}</td>"
                    f"<td>{', '.join(s['core_failed']) or '-'}</td></tr>")
    rows.append("</table>")
    rows.append("<p style='color:#555'>Core=Gateway API 필수(Support:Core), 전부 통과=공식 conformance "
                "모델의 '적합'(자체 데이터패스 측정, 공식 인증 아님). Extended=선택 기능 폭.</p>")
    return "".join(rows)


def _migration_summary_html(agg: dict, scores: dict, rubric: dict) -> str:
    caps = rubric["migration_view"]["capabilities"]
    impls = list(scores["implementations"].keys())
    measurable = {k: [c for c in caps if c["tier"] == k and c["maps_to"]]
                  for k in _TIER_ORDER}
    rows = ["<table><tr><th>구현체</th><th>🟢 표준</th><th>🟡 주의</th><th>🟠 구현체</th><th>합계</th></tr>"]
    for i in impls:
        tds = []
        tot_ok = tot_n = 0
        for k in ("standard", "caution", "vendor"):
            ok = sum(_mig_covered(_mig_cell(agg, scores, i, c["maps_to"])) for c in measurable[k])
            n = len(measurable[k])
            tds.append(f"<td>{ok}/{n}</td>")
            tot_ok += ok
            tot_n += n
        rows.append(f"<tr><td>{i}</td>" + "".join(tds) + f"<td><b>{tot_ok}/{tot_n}</b></td></tr>")
    rows.append("</table>")
    rows.append("<p style='color:#555'>구현체별로 실제 측정한 항목 중 동작하는 수. "
                "🔴 마이그레이션 불가 등급과 스펙 수준에서만 판정한 항목(미측정)은 제외. "
                "지원=동작(저수준 포함), 품질차는 상세표 참조.</p>")
    return "".join(rows)


def build_html(title: str, summary_html: str, md: str) -> str:
    # md 첫 헤딩(# 제목)을 떼어 맨 위에, 그 다음 요약표, 그 다음 본문 순서로 배치.
    lines = md.split("\n")
    head, rest = "", md
    for idx, ln in enumerate(lines):
        if ln.strip().startswith("# "):
            head = _md_to_html(ln.strip())
            rest = "\n".join(lines[:idx] + lines[idx + 1:])
            break
    return (f"<!doctype html><meta charset=utf-8><title>{title}</title><style>{_CSS}</style>"
            + head
            + '<div class="summary"><h2>한눈에</h2>' + summary_html + "</div>\n"
            + _md_to_html(rest))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--agg", default=str(GW / "results" / "aggregated.json"))
    ap.add_argument("--scores", default=str(GW / "results" / "scores.json"))
    ap.add_argument("--rubric", default=str(GW / "rubric.yaml"))
    ap.add_argument("--outdir", default=str(GW / "metrics"))
    ap.add_argument("--view", choices=["conformance", "migration", "both"], default="both")
    args = ap.parse_args()

    with open(args.agg) as f:
        agg = json.load(f)
    with open(args.scores) as f:
        scores = json.load(f)
    rubric = gwlib.load_rubric(Path(args.rubric))
    base = Path(args.outdir)

    views = ["conformance", "migration"] if args.view == "both" else [args.view]
    for v in views:
        out = base / f"{v}-view"
        out.mkdir(parents=True, exist_ok=True)
        if v == "conformance":
            md = build_conformance_markdown(agg, scores, rubric)
            html = build_html("Gateway API PoC 엄밀성 뷰",
                              _conformance_summary_html(scores), md)
        else:
            md = build_migration_markdown(agg, scores, rubric)
            html = build_html("Gateway API PoC 출발점 뷰 (ingress-nginx 마이그레이션)",
                              _migration_summary_html(agg, scores, rubric), md)
        (out / "README_tables.md").write_text(md)
        (out / "report.html").write_text(html)
        print(f"{v} → {out/'report.html'}, {out/'README_tables.md'}")


if __name__ == "__main__":
    main()
