#!/usr/bin/env python3
"""report.py: aggregated.json + scores.json + rubric.yaml → 두 뷰 리포트 (이중언어)

두 뷰(같은 측정 데이터, 다른 렌즈):
  - conformance(엄밀성): 공식 Core/Extended/채널 + 실측 + 품질/비기능 + L7 기대치.
  - migration(출발점): ingress-nginx 어노테이션 앵커 + 난이도 4등급 + 구현체매트릭스 전면.

언어: 영어(기본) + 한국어(옵션). 데이터(셀 값, 숫자, 구현체명, 버전)는 언어중립이고,
프로세(제목, 헤더, 컬럼 라벨, 인용 주석, 범례)만 TXT 카탈로그에서 가져온다.

출력(각 뷰 폴더):
  - 영어: README_tables.md, report.html
  - 한국어: README_tables_ko.md, report_ko.html

사용: python3 report.py [--agg F] [--scores F] [--rubric F] [--outdir DIR]
                        [--view conformance|migration|both] [--lang en|ko|both]
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path

import gwlib

HERE = Path(__file__).resolve().parent
GW = HERE.parent

CANARY_TEST = "canary-traffic"

# STATE_MARK: 셀 토큰. PASS/FAIL/n/a/-/FLAKY는 언어중립(영문 기호). not-configured만
# 언어별 라벨이 필요해 lang으로 분기한다.
_STATE_MARK_BASE = {"pass": "PASS", "flaky": "FLAKY", "unsupported": "n/a",
                    "no-data": "-", "fail": "FAIL"}
_NOTCFG = {"en": "not-configured", "ko": "미구성"}


def _state_mark(state: str, lang: str) -> str:
    if state == "not-configured":
        return _NOTCFG[lang]
    return _STATE_MARK_BASE.get(state, "-")


# auth(JWT, ext-authz)는 per-round 자동측정 미통합(E8, E9 라이브 검증값, 비채점 stub).
# 두 뷰가 공유하는 단일 출처. (JWT, ext-authz 구현체, ext-authz 표준 GEP-1494 필터)
# 셀 텍스트는 짧은 라벨이라 언어별 카탈로그로 분리한다(키=토큰, 값={en,ko}).
AUTH = {
    "nginx":    ("plus-only-basic",  "snippetsfilter-low",  "notimpl-404"),
    "envoy":    ("native-jwks",      "securitypolicy",      "notimpl-unsupportedvalue"),
    "istio":    ("native-jwks",      "authzpolicy-custom",  "notimpl-invalidfilter"),
    "cilium":   ("unsupported",      "unsupported",         "stdfilter-notimpl-pass"),
    "kong":     ("kgo-secret-deny",  "oss-unsupported",     "notimpl-404"),
    "traefik":  ("unsupported",      "forwardauth-native",  "accepts-but-500"),
    "kgateway": ("native-jwks",      "gatewayextension",    "stdfilter-notimpl-pass"),
}
# auth 셀 토큰 → 언어별 표시 문자열.
_AUTH_TXT = {
    "plus-only-basic":          {"en": "Plus-only (OSS is Basic-only)", "ko": "Plus전용(OSS는 Basic만)"},
    "snippetsfilter-low":       {"en": "SnippetsFilter (low-level)",    "ko": "SnippetsFilter 저수준"},
    "notimpl-404":              {"en": "not implemented (404)",         "ko": "미구현(404)"},
    "native-jwks":              {"en": "native JWKS",                   "ko": "native JWKS"},
    "securitypolicy":           {"en": "SecurityPolicy native",        "ko": "SecurityPolicy native"},
    "notimpl-unsupportedvalue": {"en": "not implemented (UnsupportedValue)", "ko": "미구현(UnsupportedValue)"},
    "authzpolicy-custom":       {"en": "AuthzPolicy CUSTOM (mesh)",     "ko": "AuthzPolicy CUSTOM(mesh)"},
    "notimpl-invalidfilter":    {"en": "not implemented (InvalidFilter)", "ko": "미구현(InvalidFilter)"},
    "unsupported":              {"en": "unsupported",                   "ko": "미지원"},
    "stdfilter-notimpl-pass":   {"en": "standard filter not implemented (passes)★", "ko": "표준필터 미구현(통과)★"},
    "kgo-secret-deny":          {"en": "KGO secret issue (deny only)",  "ko": "KGO 시크릿이슈(거부만)"},
    "oss-unsupported":          {"en": "OSS unsupported",               "ko": "OSS 미지원"},
    "forwardauth-native":       {"en": "forwardAuth native",            "ko": "forwardAuth native"},
    "accepts-but-500":          {"en": "accepts but 500",               "ko": "수용하나 500"},
    "gatewayextension":         {"en": "GatewayExtension native",       "ko": "GatewayExtension native"},
}


def _auth_label(token: str, lang: str) -> str:
    return _AUTH_TXT.get(token, {}).get(lang, token)


# canary_source.note는 aggregated.json(데이터)에 한국어로 저장된 provenance 문자열이다.
# 데이터를 바꾸지 않고, 영어 리포트 표시 시점에만 알려진 원문을 번역한다.
_CANARY_NOTE_EN = {
    "결정론 항목은 v3 캠페인 재측정, canary는 기존 155라운드 풀링 보존(발표 메트릭 동결)":
        "deterministic items re-measured in the v3 campaign, canary preserves the existing 155-round pooling "
        "(presentation metric frozen)",
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
# 문자열 카탈로그 (en=기본, ko=기존 한국어 verbatim)
# 값 안의 {0},{1},... 또는 명명 자리표시자는 .format(...)으로 데이터 주입.
# ===========================================================================
TXT = {
    "en": {
        # ---- conformance ----
        "c_title": "Gateway API PoC, rigor view (Gateway API {gwv}, {basis})",
        "c_basis": "deterministic {rounds} rounds",
        "c_basis_canary": ", canary {n}-round pool",
        "c_intro_rounds": "> **Round basis**: deterministic items use the v3 campaign {rounds} rounds, canary "
            "(weighted routing) uses a frozen {canary}-round pool (presentation metric frozen). "
            "The two axes have different round counts, and the canary verdict in section 2 is based on the "
            "155-round pooling (section 3).",
        "c_intro_lens": "> **Live verification** aligned to the official spec (Core/Extended/channel), plus "
            "**quality/non-functional metrics** that conformance does not see (canary distribution, load, "
            "robustness). For the starting-point (migration) view see `../migration-view/`.",
        "c_s1_h": "## 1. Summary (conformance)",
        "c_s1_note1": "> Official Gateway API conformance is scored **per channel** (Core + Extended). We "
            "measure with the **experimental-channel CRDs** (a superset of standard), so we see both channels.",
        "c_s1_note2": "> Scoring = **Core {ncore}** (required, Support:Core) + **Extended (standard) {next}** (stable) "
            "+ **Extended (experimental) {nxe}** (fields may change). "
            "experimental fields (no conformance feature), implementation extensions, and non-functional items are "
            "unscored (sections 5 to 8).",
        "c_s1_cols": "| Implementation | Version | Core ({ncore}) | Extended-std ({next}) | Extended-exp ({nxe}) | Failed Core |",
        "c_s1_pass": "{cp}/{n} conformant",
        "c_s1_fail": "{cp}/{n} (below)",
        "c_s1_b1": "> **Core N/7 conformant**: Support:Core required features. All pass = \"conformant\" in the "
            "official model. Missing optional (Extended) features do not affect conformance.",
        "c_s1_b2": "> **Extended on 2 channel axes**: `std`=standard channel (stable), `exp`=experimental channel "
            "(fields may change). Both are Extended features of official conformance and differ only by channel "
            "(GEP-1709: conformance is scored per channel). v1.4 experimental Extended is small, so the exp axis "
            "holds {nxe} (CORS etc.).",
        "c_s1_b3": "> ⚠️ This table is **our own data-path measurement aligned to the official model**, not an "
            "**official certification** in the upstream suite registry (agreement with the official v1.4.0 report "
            "confirmed against primary sources).",
        "c_s1_version": "> **Version note (snapshot)**: this is as of the measurement-time version, and some "
            "unsupported items have since been resolved in later releases (confirmed via the 2026-06-10 official "
            "conformance/CHANGELOG). Traefik backend-request-header-mod is **supported in 3.7** (measured 3.6.17), "
            "kgateway backend-tls is **supported in 2.3.0** (measured 2.2.2), Cilium backend-tls/ExternalAuth is "
            "**supported in 1.20** (measured 1.19.4, 1.20 GA imminent), Kong TLSRoute is **supported in KGO 2.2.0** "
            "(measured 2.1.x). When citing, state the measured version alongside.",
        "c_s2_h": "## 2. Per-item detail (scored {tot}: Core {ncore} + Extended-std {next} + Extended-exp {nxe})",
        "c_s2_col_test": "Test",
        "c_s2_col_cat": "Category",
        "c_lv_core": "Core (required)",
        "c_lv_extstd": "Extended-std",
        "c_lv_extexp": "Extended-exp",
        "c_diff_common": " ◇common",
        "c_diff_diff": " ◆differentiating",
        "c_s2_b1": "> canary is a sampled test, so PASS/FAIL is decided by cumulative pooled split (2σ). "
            "**Click the row name `canary-traffic`** to jump to the per-implementation split detail (section 3).",
        "c_s2_b2": "> ◇common=supported by all 7 (migration-safe guarantee), ◆differentiating=splits by "
            "implementation. Only items holding a v1.4 standard-channel conformance flag are graded.",
        "c_s3_h": "## 3. canary quality metrics (weighted routing 80/20, pooled)",
        "c_s3_cols": "| Implementation | Cumulative split (v1%) | Samples | Per-round mean v1 | min~max | 2σ-excursion rounds |",
        "c_s3_source": "> **Source**: {note}",
        "c_s3_b1": "> **Cumulative split (v1%)**: the actual distribution ratio summing v1/v2 requests over all "
            "rounds (target 80%). canary PASSes when this converges within 2σ of the target.",
        "c_s3_b2": "> **2σ-excursion rounds**: the number of rounds whose v1 count out of 50 requests fell outside "
            "the statistical 2σ band **[35,45]** (target 40±2σ, with sigma=2.83 the integer band is 35 to 45), over "
            "the total. e.g. `5/155` = 5 of 155 rounds outside the band. Under sampling noise about 5%/round is "
            "normal excursion, so this is **not a failure but a distribution-quality reference** (which is why the "
            "verdict uses cumulative pooling, not per-round).",
        "c_s4_h": "## 4. experimental fields (no conformance feature, not scorable, capability report)",
        "c_s4_note": "> These exist in the API as experimental **fields** but v1.4 conformance has **no feature "
            "(test) for them** (unlike experimental Extended such as CORS, which is scored in section 2).",
        "c_s4_retry_pass_n": "{i} {n} attempts",
        "c_s4_retry_pass": "{i} supported",
        "c_s4_retry_infra": " (routing failed in some rounds)",
        "c_s4_retry_unsup": "{i} not applied",
        "c_s4_retry_note": "> **retry detail** (HTTPRoute standard retry field `retry.attempts:3,codes:[503]`, "
            "upstream attempts per request on 503): {body}. Differences in attempt count reflect each "
            "implementation's retry policy (istio/kgateway are more aggressive). '(routing failed in some rounds)' "
            "means that implementation failed route programming in some rounds and those rounds were excluded from "
            "the denominator.",
        "c_s5_h": "## 5. Implementation feature matrix (outside the Gateway API standard, conformance-irrelevant)",
        "c_s5_note": "> Not in the standard, provided by implementation-specific mechanisms. Compared as native / "
            "low-level-config / unsupported.",
        "c_s5_fairness": "> **Measurement-setting note (fairness, re-verified 2026-06-10)**: some items only work "
            "when the implementation's recommended setting is enabled. Kong was measured with "
            "`router_flavor=expressions` for query-param/method matching (the OSS default traditional_compatible "
            "lacks query-param, so measuring with the default scores lower). kgateway basic-auth works via "
            "TrafficPolicy basicAuth (native). Cilium rate-limiting/body-size were marked unsupported because there "
            "is no declarative standard or implementation path, but they are possible via raw CiliumEnvoyConfig (a low-level "
            "escape hatch on par with istio EnvoyFilter; unmeasured). Istio tls-passthrough stays unsupported even "
            "with the alpha flag (PILOT_ENABLE_ALPHA_GATEWAY_API) because it does not work in v1.4 (istio TLSRoute is "
            "officially conformant only for Terminate, passthrough unverified, issue #47366).",
        "c_s6_h": "## 6. Non-functional / operational metrics (not features: performance, robustness, recovery)",
        "c_fo_zero": "{i} no outage",
        "c_fo_recover": "{i} recovery ~{rs}s",
        "c_fo_excl": "{i} excluded (shared eBPF)",
        "c_fo_note": "> **failover-recovery detail** (recovery after a forced data-plane restart, separate "
            "rounds-ops campaign): {body}. no outage=no traffic loss during pod replacement (outage 0), "
            "recovery ~Ns=normalized after about N seconds of gap. All confirmed disrupted by pod replacement "
            "(pod_changed).",
        "c_hc_sup": "{i} supported",
        "c_hc_unsup": "{i} unsupported",
        "c_hc_note": "> **health-check detail** (does active health checking eject an unhealthy backend from the "
            "pool. good 2 + bad 1 (/health 503) backends, supported when bad is fully removed, rounds-ops): "
            "{body}. supported=active probe of envoy BackendTrafficPolicy / kong KongUpstreamPolicy / kgateway "
            "BackendConfigPolicy. unsupported=no active HC exposed (nginx Plus-only, istio is a mesh outlier, "
            "cilium/traefik not exposed).",
        "c_cr_note": "> **config-robustness measurement condition**: 'does basic routing survive when all features "
            "are deployed at once'. The values above are based on the standard feature set (deterministic campaign). "
            "kong is sensitive to config-load, so under a heavier setup that also stacks the operational-test "
            "policies (rounds-ops campaign) the same item drops to fragile. This matches kong's all-or-nothing "
            "config model, and the robust label above is limited to the standard-setting scenario.",
        "c_s7_h": "## 7. auth (theme: implementation/experimental mixed, migration-critical)",
        "c_s7_note": "> Not a category but a **thematic cross-section**: auth is scattered across the taxonomy. "
            "**JWT=implementation (section-5 type, no standard)**, **ext-authz standard filter=experimental "
            "(GEP-1494)**, **ext-authz implementation=implementation**. It is the crux of ingress-nginx auth-url "
            "migration, so it is gathered in one place. Live verification values for 7 implementations (E8, E9), "
            "per-round automated measurement not integrated (unscored).",
        "c_s7_cols": "| Implementation | JWT | ext-authz (impl) | ext-authz (standard GEP-1494 filter) |",
        "c_s7_b": "> ★ The GEP-1494 standard ExternalAuth filter is enforced by no implementation. "
            "envoy/nginx/istio/kong/traefik reject or error, while cilium/kgateway do not implement the standard "
            "filter, so unauthenticated traffic passes through as-is (silent no-op). GEP-1494 is at the experimental "
            "stage and does not specify a failure mode (fail-open/closed) (there is no 'MUST fail closed' wording in "
            "the spec; PR #4001 deferred failure semantics). cilium provides ext-authz only in 1.20, kgateway only "
            "via its own TrafficPolicy. Conclusion: the standard filter is not yet usable as production auth and an "
            "implementation CRD is required.",
        "c_s8_h": "## 8. flake / data note (canary excluded, see section 3)",
        "c_s8_row": "- {i}: {parts} (pass rate 0<p<1, unscored matrix)",
        "c_s8_none": "- (currently no non-canary flakes)",
        "c_s9_h": "## 9. Data note: not-configured (not integrated into automated rounds)",
        "c_s9_note": "> Items with no round data because they are not integrated into the automated round loop. "
            "They split into two kinds. (a) **auth-jwt/auth-extauth are measured**. They were live-verified (E8/E9) "
            "and the values are in the section-7 auth table. Only the automated-loop integration is deferred, so they "
            "merely show as `not-configured` in rounds, not as missing data. (b) **The rest are unmeasured** (no live "
            "logic, re-measurement targets). All are unscored, so grade is unaffected.",
        "c_s9_done": "measured (E8/E9, see section 7): {items}",
        "c_s9_gap": "unmeasured: {items}",
        # at-a-glance summary (conformance)
        "c_sum_cols": ("<table><tr><th>Implementation</th><th>Core (required)</th>"
                       "<th>Extended (optional)</th><th>Failed Core</th></tr>"),
        "c_sum_pass": "{cp}/{n} conformant",
        "c_sum_fail": "{cp}/{n} (below)",
        "c_sum_foot": "<p style='color:#555'>Core=Gateway API required (Support:Core), all pass="
                      "'conformant' in the official conformance model (our own data-path measurement, not official "
                      "certification). Extended=optional feature breadth.</p>",
        "html_title_conf": "Gateway API PoC, rigor view",
        "html_title_mig": "Gateway API PoC, starting-point view (ingress-nginx migration)",
        "at_a_glance": "At a glance",
        # ---- migration ----
        "m_title": "Gateway API PoC, starting-point view (ingress-nginx → Gateway API {gwv} migration)",
        "m_lens": "> **What sets this view apart**: unlike official conformance (declared PASS/FAIL) and "
            "ingress2gateway (whether mechanical conversion happens), it cross-compares, on one yardstick, live "
            "cluster **measurement** + **implementation features** outside conformance scope (rate-limit, auth, "
            "body-size) + the **feature-breadth gap** within conformant implementations. For the rigor (spec) view "
            "see `../conformance-view/`.",
        "m_basis": "> **Measurement basis: Gateway API {gwv}** (2026-06 measurement time, ingress2gateway {i2gw}). "
            "Difficulty grades are based on this version. **v1.5 (released 2026-04-21) new features** (mTLS client "
            "etc.) are outside the v1.4 measurement scope, so they are marked `TBD(v1.5)` and are targets for the "
            "next re-baseline (re-baseline is after Cilium 1.20 stable, expected late July). By contrast **CORS, "
            "external auth, and TLSRoute were already measured on all 7 in the v1.4 experimental channel**, and if "
            "promoted to the standard channel in v1.5 they can move from 🟡 to 🟢. Cell-value sources are the same as "
            "the rigor view's measurement (same measurement data).",
        "m_s1_h": "## 1. Four migration-difficulty grades",
        "m_s1_cols": "| Grade | Meaning |",
        "m_s2_h": "## 2. Per-implementation coverage (by measurable items)",
        "m_s2_note": "> *\"If I move my ingress-nginx to this implementation, how many per grade actually work.\"* "
            "It counts only the items actually measured per implementation. Excluded are the 🔴 migration-impossible "
            "grade, items judged only at the Gateway API spec level regardless of implementation (`(not measured)` in "
            "the table), and structural rows with no measurement mapping (e.g. mTLS client=`TBD(v1.5)`). So the "
            "per-grade denominator can be smaller than the row count in the section-3 checklist (e.g. 🟡 is based on 7 "
            "of the 8 checklist rows, excluding mTLS).",
        "m_s2_col_impl": "Implementation",
        "m_s2_total": "Total",
        "m_s2_b": "> Supported = **works** (includes low-level-config/snippet). It counts only whether it works; the "
            "quality gap (native vs low-level) is shown by the section-3 detail table. External auth is based on "
            "implementation native (the GEP-1494 standard filter is enforced by no one, rigor view section 7).",
        "m_s3_h": "## 3. Migration checklist ({n} items, by difficulty group)",
        "m_s3_legend": "> **Legend: i2gw conversion** (ingress2gateway {i2gw} **run directly per annotation**, "
            "before/after manifests under `migration/i2gw/`): `✓` auto-converted / `~` partial/best-effort (or some "
            "annotations rejected) / `✗` not converted (manual redesign) / `native` a base Ingress feature so not a "
            "conversion target (easiest). **Converted ≠ works**. The implementation cell (PASS/native etc.) shows "
            "actual support.",
        "m_s3_grade_cols": "| Feature | ingress-nginx annotation | Importance | GW API v1.4 | i2gw | ",
        "m_s3_notes_h": "> ※ traps/notes:",
        "m_s4_h": "## 4. How to read / sources / limits",
        "m_s4_l1": "- **Reading cells**: 🟢🟡 grades are live `PASS/FAIL/n/a`. 🟠 implementation is the "
            "`native/low-level-config/unsupported` matrix. auth uses live-verified values (rigor section 7). "
            "`(not measured)` is an item not measured per implementation but judged only at the Gateway API spec "
            "level (e.g. snippet has no equivalent in any implementation).",
        "m_s4_l2": "- **i2gw conversion**: a **measured value** that **ran ingress2gateway {i2gw} directly** on a "
            "sample Ingress per annotation and recorded conversion results/warnings (not a research estimate). "
            "before/after manifests + logs + classification basis are under `migration/i2gw/` (ingress/, gateway/, "
            "logs/, results.json). `✓`=auto-converted, `~`=partial/some rejected, `✗`=not converted (manual "
            "redesign), `native`=a base Ingress feature so not a conversion target.",
        "m_s4_l3": "- **Excluded from the checklist**: Gateway API new standard features not in ingress-nginx, such "
            "as method matching and query-param matching, are not in this checklist. They are not things to \"carry "
            "over\" in migration but features gained additionally after moving (measured in the rigor view).",
        "m_s4_l4": "- **Importance (high/medium/low)**: real-world ingress-nginx usage importance. It is "
            "directional. With no public quantitative survey, it synthesizes the signal that maintainers singled out "
            "snippet as \"most depended on + most dangerous\" and the emphasis in the migration guide.",
        "m_s4_l5": "- **Sources (primary)**: ingress-nginx retirement announcement (2025-11-11), \"Before You "
            "Migrate\" (2026-02-27), ingress2gateway 1.0 (2026-03-20), IngressNightmare CVE-2025-1974, Reddit "
            "\"Gateway API for Ingress-NGINX, a Maintainer's Perspective\".",
        "m_s4_l6": "- **Limits**: many 🟡 (CORS, external auth, mTLS client, TLSRoute) are v1.4 experimental channel "
            "and slated for Standard promotion in v1.5, so the grade may rise depending on timing. 🔴 snippet is "
            "permanently unsupported by design (redesign required).",
        "m_cell_notmeasured": "(not measured)",
        "m_imp_high": "High", "m_imp_medium": "Medium", "m_imp_low": "Low",
        # at-a-glance summary (migration)
        "m_sum_cols": ("<table><tr><th>Implementation</th><th>🟢 Standard</th><th>🟡 Caution</th>"
                       "<th>🟠 Implementation</th><th>Total</th></tr>"),
        "m_sum_foot": "<p style='color:#555'>Of items actually measured per implementation, how many work. "
                      "Excludes the 🔴 migration-impossible grade and items judged only at the spec level (not "
                      "measured). Supported=works (incl. low-level), see the detail table for the quality gap.</p>",
        "m_tier_short": {"standard": "Standard", "caution": "Caution", "vendor": "Implementation", "blocked": "Blocked"},
    },
    "ko": {
        # ---- conformance ---- (기존 한국어 verbatim)
        "c_title": "Gateway API PoC 엄밀성 뷰 (Gateway API {gwv}, {basis})",
        "c_basis": "결정론 {rounds} rounds",
        "c_basis_canary": ", canary {n}라운드 풀",
        "c_intro_rounds": "> **라운드 근거**: 결정론(determinstic) 항목은 v3 캠페인 {rounds}라운드, "
            "canary(가중 라우팅)는 동결된 {canary}라운드 풀이다(발표 메트릭 동결). "
            "두 축의 라운드 수가 다르며, 섹션 2의 canary 행 판정은 155라운드 풀링(섹션 3)에 근거한다.",
        "c_intro_lens": "> 공식 스펙(Core/Extended/채널)에 정렬한 **실측 검증** + conformance가 보지 않는 "
            "**품질/비기능 지표**(canary 분포, 부하, 견고성). 출발점(마이그레이션) 뷰는 "
            "`../migration-view/` 참조.",
        "c_s1_h": "## 1. 요약 (conformance)",
        "c_s1_note1": "> 공식 Gateway API conformance는 **채널별**로 채점된다(Core+Extended). 우리는 "
            "**experimental 채널 CRD**(standard 상위집합)로 측정하므로 두 채널 모두 본다.",
        "c_s1_note2": "> 채점 = **Core {ncore}**(필수, Support:Core) + **Extended(standard) {next}**(안정) "
            "+ **Extended(experimental) {nxe}**(필드 변경 가능). "
            "experimental 필드(conformance 기능 없음), 구현체, 비기능은 비채점(섹션 5~8).",
        "c_s1_cols": "| 구현체 | 버전 | Core ({ncore}) | Extended-std ({next}) | Extended-exp ({nxe}) | 미통과 Core |",
        "c_s1_pass": "{cp}/{n} 통과",
        "c_s1_fail": "{cp}/{n} (미달)",
        "c_s1_b1": "> **Core N/7 통과**: Support:Core 필수 기능. 전부 통과 = 공식 모델의 \"conformant\". "
            "선택(Extended) 미지원은 적합성에 무영향.",
        "c_s1_b2": "> **Extended는 채널 2축**: `std`=standard 채널(안정), `exp`=experimental 채널(필드 변경 가능). "
            "둘 다 공식 conformance의 Extended 기능이며 채널만 다르다(GEP-1709: conformance는 채널별 채점). "
            "v1.4 experimental Extended는 적어 exp 축은 {nxe}항목(CORS 등).",
        "c_s1_b3": "> ⚠️ 이 표는 **공식 모델에 정렬된 자체 데이터패스 측정**이지 upstream 스위트 등재 **공식 인증은 아님** "
            "(공식 v1.4.0 리포트와 일치함은 1차소스로 확인).",
        "c_s1_version": "> **버전 주의(스냅샷)**: 측정 시점 버전 기준이며, 이후 릴리스에서 일부 미지원이 해소됐다 "
            "(2026-06-10 공식 conformance/CHANGELOG로 확인). Traefik backend-request-header-mod는 "
            "**3.7에서 지원**(측정 3.6.17), kgateway backend-tls는 **2.3.0에서 지원**(측정 2.2.2), "
            "Cilium backend-tls/ExternalAuth는 **1.20에서 지원**(측정 1.19.4, 1.20 GA 임박), "
            "Kong TLSRoute는 **KGO 2.2.0에서 지원**(측정 2.1.x). 인용 시 측정 버전을 함께 밝힌다.",
        "c_s2_h": "## 2. 항목별 상세 (채점 {tot}: Core {ncore} + Extended-std {next} + Extended-exp {nxe})",
        "c_s2_col_test": "테스트",
        "c_s2_col_cat": "구분",
        "c_lv_core": "Core(필수)",
        "c_lv_extstd": "Extended-std",
        "c_lv_extexp": "Extended-exp",
        "c_diff_common": " ◇공통",
        "c_diff_diff": " ◆차별",
        "c_s2_b1": "> canary는 표본 테스트라 누적 풀링 split(2σ)으로 PASS/FAIL 판정한다. "
            "**행 이름 `canary-traffic`을 누르면** 구현체별 세부 split 비율(섹션 3)로 이동한다.",
        "c_s2_b2": "> ◇공통=7종 전부 지원(마이그레이션 안전 보증), ◆차별=구현체별 갈림. "
            "v1.4 standard 채널 conformance flag 보유 항목만 graded.",
        "c_s3_h": "## 3. canary 품질 지표 (가중 라우팅 80/20, 풀링)",
        "c_s3_cols": "| 구현체 | 누적 split(v1%) | 표본수 | 라운드 평균 v1 | min~max | 2σ이탈 라운드 |",
        "c_s3_source": "> **출처**: {note}",
        "c_s3_b1": "> **누적 split(v1%)**: 전 라운드 v1/v2 요청을 합산한 실제 분배 비율(목표 80%). "
            "이게 목표에 2σ 내로 수렴하면 canary PASS.",
        "c_s3_b2": "> **2σ이탈 라운드**: 라운드마다 50요청 중 v1 횟수가 통계적 2σ 구간 **[35,45]**(목표 40±2σ, "
            "sigma=2.83이라 정수 구간 35~45)을 벗어난 라운드 수 / 전체. 예 `5/155` = 155라운드 중 5라운드가 구간 밖. "
            "표본 노이즈상 약 5%/라운드는 정상 이탈이라 **실패가 아니라 분포 품질 참고치**다"
            "(그래서 판정은 라운드별이 아닌 누적 풀링으로 한다).",
        "c_s4_h": "## 4. experimental 필드 (conformance 기능 없음, 채점 불가, 역량 보고)",
        "c_s4_note": "> API에 experimental **필드**로 존재하나 v1.4 conformance **기능(테스트) 자체가 없다**"
            "(CORS 같은 experimental Extended와 다름 → 그건 섹션 2에 채점됨).",
        "c_s4_retry_pass_n": "{i} {n}회 시도",
        "c_s4_retry_pass": "{i} 지원",
        "c_s4_retry_infra": "(일부 라운드 라우팅 실패)",
        "c_s4_retry_unsup": "{i} 미적용",
        "c_s4_retry_note": "> **retry 상세**(HTTPRoute 표준 retry 필드 `retry.attempts:3,codes:[503]`, "
            "503에 1 요청당 업스트림 시도 수): {body}. 시도 수 차이는 구현체 retry 정책(istio/kgateway가 더 공격적). "
            "'(일부 라운드 라우팅 실패)'는 해당 구현체가 일부 라운드에서 라우트 프로그래밍에 "
            "실패해 그 라운드를 분모에서 제외했다는 뜻.",
        "c_s5_h": "## 5. 구현체 기능 매트릭스 (Gateway API 표준 외, conformance 무관)",
        "c_s5_note": "> 표준에 없고 구현체 고유 메커니즘으로 제공. native / low-level-config / unsupported로 비교.",
        "c_s5_fairness": "> **측정 설정 주의(공정성, 2026-06-10 재검증)**: 일부 항목은 구현체 권장 설정을 켜야 "
            "동작한다. Kong은 query-param/method 매칭을 위해 `router_flavor=expressions`로 측정했다"
            "(OSS 디폴트 traditional_compatible은 query-param 미지원, 즉 디폴트로 재면 더 낮게 나온다). "
            "kgateway basic-auth는 TrafficPolicy basicAuth로 동작(native). Cilium rate-limiting/body-size는 "
            "선언형 표준이나 구현체 경로가 없어 unsupported로 적었으나, raw CiliumEnvoyConfig(istio EnvoyFilter와 "
            "동급 저수준 escape hatch)로는 가능하다(미측정). Istio tls-passthrough는 alpha 플래그"
            "(PILOT_ENABLE_ALPHA_GATEWAY_API)를 켜도 v1.4에서 미동작이라 미지원(istio TLSRoute는 Terminate만 "
            "공식 conformant, passthrough 미검증, 이슈 #47366).",
        "c_s6_h": "## 6. 비기능 / 운영 지표 (기능 아님, 성능, 견고성, 복구)",
        "c_fo_zero": "{i} 무중단",
        "c_fo_recover": "{i} 복구~{rs}s",
        "c_fo_excl": "{i} 측정제외(공유 eBPF)",
        "c_fo_note": "> **failover-recovery 상세**(데이터플레인 강제 재시작 후 복구, rounds-ops 별도 캠페인): "
            "{body}. 무중단=파드 교체 중 트래픽 무손실(outage 0), "
            "복구~Ns=약 N초 공백 후 정상화. 모두 파드 교체(pod_changed)로 교란 확인됨.",
        "c_hc_sup": "{i} 지원",
        "c_hc_unsup": "{i} 미지원",
        "c_hc_note": "> **health-check 상세**(능동 health check가 unhealthy 백엔드를 풀에서 빼는가. "
            "good 2 + bad 1(/health 503) 백엔드, bad 완전 제거 시 지원, rounds-ops): "
            "{body}. 지원=envoy BackendTrafficPolicy / kong KongUpstreamPolicy / "
            "kgateway BackendConfigPolicy의 능동 probe. 미지원=능동 HC 미노출"
            "(nginx는 Plus 전용, istio는 mesh outlier, cilium/traefik 미노출).",
        "c_cr_note": "> **config-robustness 측정 조건**: '모든 기능을 동시에 배포했을 때 기본 라우팅이 "
            "살아남는가'. 위 값은 표준 기능셋(결정론 캠페인) 기준이다. kong은 config-load에 "
            "민감해, 운영 테스트 정책까지 동시에 얹은 더 무거운 설정(rounds-ops 캠페인)에선 같은 "
            "항목이 fragile로 떨어진다. kong의 all-or-nothing 설정 모델 특성과 일치하며, 위 robust "
            "표기는 표준 설정 시나리오 한정이다.",
        "c_s7_h": "## 7. auth (주제: 구현체/실험 혼재, 마이그레이션 핵심)",
        "c_s7_note": "> 카테고리가 아니라 **주제 단면**: auth는 분류상 흩어져 있다. **JWT=구현체(섹션 5형, 표준 없음)**, "
            "**ext-authz 표준필터=experimental(GEP-1494)**, **ext-authz 구현체=구현체**. ingress-nginx auth-url "
            "마이그레이션 핵심이라 한 곳에 모음. 7종 라이브 검증값(E8, E9), per-round 자동측정 미통합(비채점).",
        "c_s7_cols": "| 구현체 | JWT | ext-authz(구현체) | ext-authz(표준 GEP-1494 필터) |",
        "c_s7_b": "> ★ GEP-1494 표준 ExternalAuth 필터는 어떤 구현체도 강제하지 못한다. "
            "envoy/nginx/istio/kong/traefik은 거부 또는 오류, cilium/kgateway는 표준 필터를 "
            "구현하지 않아 무인증 트래픽이 그대로 통과한다(silent no-op). GEP-1494는 experimental "
            "단계라 실패모드(fail-open/closed)를 규정하지 않는다(스펙에 'MUST fail closed' 문구 없음, "
            "PR #4001에서 실패 의미 보류). cilium은 1.20, kgateway는 자체 TrafficPolicy로만 ext-authz를 "
            "제공한다. 결론: 표준 필터는 아직 프로덕션 auth로 못 쓰고 구현체 CRD가 필요하다.",
        "c_s8_h": "## 8. 플레이크 / 데이터 주의 (canary 제외, 섹션 3 참조)",
        "c_s8_row": "- {i}: {parts} (통과율 0<p<1, 비채점 매트릭스)",
        "c_s8_none": "- (현재 비-canary 플레이크 없음)",
        "c_s9_h": "## 9. 데이터 주의: not-configured (자동 라운드 미통합)",
        "c_s9_note": "> 자동 라운드 루프에 통합되지 않아 round 데이터가 없는 항목. 두 종류로 갈린다. "
            "(a) **auth-jwt/auth-extauth는 측정 완료**다. 라이브 검증(E8/E9)했고 값은 7절 auth 표에 "
            "있다. 자동 루프 통합만 보류라 round에는 `미구성`으로 찍힐 뿐 데이터가 없는 게 아니다. "
            "(b) **그 외는 미측정**(라이브 로직 부재, 재측정 대상). 모두 비채점이라 등급 무관.",
        "c_s9_done": "측정완료(E8/E9, 7절 참조): {items}",
        "c_s9_gap": "미측정: {items}",
        "c_sum_cols": ("<table><tr><th>구현체</th><th>Core(필수)</th>"
                       "<th>Extended(선택)</th><th>미통과 Core</th></tr>"),
        "c_sum_pass": "{cp}/{n} 통과",
        "c_sum_fail": "{cp}/{n} (미달)",
        "c_sum_foot": "<p style='color:#555'>Core=Gateway API 필수(Support:Core), 전부 통과=공식 conformance "
                      "모델의 '적합'(자체 데이터패스 측정, 공식 인증 아님). Extended=선택 기능 폭.</p>",
        "html_title_conf": "Gateway API PoC 엄밀성 뷰",
        "html_title_mig": "Gateway API PoC 출발점 뷰 (ingress-nginx 마이그레이션)",
        "at_a_glance": "한눈에",
        # ---- migration ----
        "m_title": "Gateway API PoC 출발점 뷰 (ingress-nginx → Gateway API {gwv} 마이그레이션)",
        "m_lens": "> **이 뷰의 차별점**: 공식 conformance(선언 PASS/FAIL), ingress2gateway(기계 변환 여부)와 달리, "
            "라이브 클러스터 **실측** + conformance 범위 밖 **구현체 기능**(rate-limit, auth, body-size) + "
            "conformant 내부의 **기능폭 격차**를 같은 잣대로 나란히 비교한다. 엄밀성(스펙) 뷰는 "
            "`../conformance-view/` 참조.",
        "m_basis": "> **측정 기준: Gateway API {gwv}** (2026-06 측정 시점, ingress2gateway {i2gw}). "
            "난이도 등급은 이 버전 기준이다. **v1.5(2026-04-21 릴리스) 신규 기능**(mTLS 클라이언트 등)은 "
            "v1.4 측정 범위 밖이라 `TBD(v1.5)`로 표기하고 차기 재베이스라인 대상이다"
            "(재베이스라인은 Cilium 1.20 stable, 7월 말 예정 이후). "
            "반면 **CORS, 외부 인증, TLSRoute는 v1.4 experimental 채널에서 이미 7종 실측**했으며, "
            "v1.5에서 표준 채널로 승격되면 🟡→🟢으로 올라갈 수 있다. "
            "셀 값 출처는 엄밀성 뷰의 실측과 동일(같은 측정 데이터).",
        "m_s1_h": "## 1. 마이그레이션 난이도 4등급",
        "m_s1_cols": "| 등급 | 의미 |",
        "m_s2_h": "## 2. 구현체별 커버리지 (측정 가능 항목 기준)",
        "m_s2_note": "> *\"내 ingress-nginx를 이 구현체로 옮기면 등급별로 몇 개가 실제 동작하나.\"* "
            "구현체별로 실제 측정한 항목만 센다. 🔴 마이그레이션 불가 등급과, 구현체와 무관하게 "
            "Gateway API 스펙 수준에서만 판정한 항목(표에서 `(미측정)`), 그리고 측정 매핑이 없는 "
            "구조적 행(예: mTLS 클라이언트=`TBD(v1.5)`)은 제외한다. 그래서 등급별 분모가 3절 "
            "점검표의 행 수보다 작을 수 있다(예: 🟡은 점검표 8행 중 mTLS를 뺀 7개 기준).",
        "m_s2_col_impl": "구현체",
        "m_s2_total": "합계",
        "m_s2_b": "> 지원 = **동작**(low-level-config/snippet 저수준 포함). 동작 여부만 세고 품질차(native vs 저수준)는 "
            "3절 상세표가 보여준다. 외부 auth는 구현체 native 기준(GEP-1494 표준 필터는 아무도 강제 못 함, "
            "엄밀성 뷰 7절).",
        "m_s3_h": "## 3. 마이그레이션 점검표 ({n}개, 난이도 그룹)",
        "m_s3_legend": "> **범례: i2gw 변환**(ingress2gateway {i2gw}을 어노테이션별로 **직접 실행한 실측**, "
            "before/after manifest는 `migration/i2gw/`): "
            "`✓` 자동변환 / `~` 부분/best-effort(또는 일부 어노테이션 거절) / `✗` 미변환(수동 재설계) / "
            "`native` Ingress 기본기능이라 변환 대상 아님(가장 쉬움). "
            "**변환됨 ≠ 동작함**. 구현체 셀(PASS/native 등)이 실제 지원을 보여준다.",
        "m_s3_grade_cols": "| 기능 | ingress-nginx 어노테이션 | 중요도 | GW API v1.4 | i2gw | ",
        "m_s3_notes_h": "> ※ 함정/주석:",
        "m_s4_h": "## 4. 읽는 법 / 출처 / 한계",
        "m_s4_l1": "- **셀 읽기**: 🟢🟡 등급은 실측 `PASS/FAIL/n/a`. 🟠 구현체는 `native/low-level-config/unsupported` "
            "매트릭스. auth는 라이브 검증값(엄밀성 7절). `(미측정)`은 구현체별로 측정하지 않고 "
            "Gateway API 스펙 수준에서만 판정한 항목(예: snippet은 어느 구현체든 등가물이 없음).",
        "m_s4_l2": "- **i2gw 변환**: ingress2gateway {i2gw}을 어노테이션별 샘플 Ingress로 **직접 실행**해 "
            "변환 결과/경고를 기록한 **실측값**(연구 추정 아님). before/after manifest + 로그 + 분류 근거는 "
            "`migration/i2gw/`(ingress/, gateway/, logs/, results.json). `✓`=자동변환, `~`=부분/일부 거절, "
            "`✗`=미변환(수동 재설계), `native`=Ingress 기본기능이라 변환 대상 아님.",
        "m_s4_l3": "- **점검표에서 제외한 것**: method 매칭, query-param 매칭처럼 ingress-nginx에 없던 Gateway API "
            "신규 표준 기능은 이 점검표에 넣지 않았다. 마이그레이션으로 \"넘어갈 것\"이 아니라 옮긴 뒤 "
            "추가로 얻는 기능이기 때문이다(엄밀성 뷰에서 측정).",
        "m_s4_l4": "- **중요도(상/중/하)**: ingress-nginx 실사용 중요도. directional이다. 공개 정량 survey가 없어, "
            "메인테이너가 snippet을 \"가장 의존+가장 위험\"으로 지목한 신호와 마이그레이션 가이드 강조를 종합했다.",
        "m_s4_l5": "- **출처(1차)**: ingress-nginx 은퇴 발표(2025-11-11), \"Before You Migrate\"(2026-02-27), "
            "ingress2gateway 1.0(2026-03-20), IngressNightmare CVE-2025-1974, "
            "Reddit \"Gateway API for Ingress-NGINX, a Maintainer's Perspective\".",
        "m_s4_l6": "- **한계**: 🟡 다수(CORS, 외부 인증, mTLS 클라이언트, TLSRoute)는 v1.4 실험채널이며 v1.5에서 Standard 승격 "
            "예정 → 시점에 따라 등급 상향 가능. 🔴 snippet은 설계상 영구 미지원(재설계 필수).",
        "m_cell_notmeasured": "(미측정)",
        "m_imp_high": "상", "m_imp_medium": "중", "m_imp_low": "하",
        "m_sum_cols": ("<table><tr><th>구현체</th><th>🟢 표준</th><th>🟡 주의</th><th>🟠 구현체</th><th>합계</th></tr>"),
        "m_sum_foot": "<p style='color:#555'>구현체별로 실제 측정한 항목 중 동작하는 수. "
                      "🔴 마이그레이션 불가 등급과 스펙 수준에서만 판정한 항목(미측정)은 제외. "
                      "지원=동작(저수준 포함), 품질차는 상세표 참조.</p>",
        "m_tier_short": {"standard": "표준", "caution": "주의", "vendor": "구현체", "blocked": "불가"},
    },
}


# ===========================================================================
# 엄밀성 뷰 (conformance)
# ===========================================================================
def build_conformance_markdown(agg: dict, scores: dict, rubric: dict, lang: str = "en") -> str:
    T = TXT[lang]
    groups = gwlib.level_groups(rubric)
    impls = list(scores["implementations"].keys())
    L = []
    cs = agg.get("canary_source") or {}
    canary_rounds = cs.get("rounds_sampled")
    basis = T["c_basis"].format(rounds=scores.get("rounds"))
    if canary_rounds:
        basis += T["c_basis_canary"].format(n=canary_rounds)
    L.append("# " + T["c_title"].format(gwv=scores.get("gateway_api_version"), basis=basis) + "\n")
    L.append(T["c_intro_rounds"].format(rounds=scores.get("rounds"), canary=canary_rounds or "155") + "\n")
    L.append(T["c_intro_lens"] + "\n")

    # 1. 요약
    n_core = len(groups["core"])
    n_ext = len(groups["extended-standard"])
    n_xe = len(groups["extended-experimental"])
    L.append(T["c_s1_h"] + "\n")
    L.append(T["c_s1_note1"] + "\n")
    L.append(T["c_s1_note2"].format(ncore=n_core, next=n_ext, nxe=n_xe) + "\n")
    L.append(T["c_s1_cols"].format(ncore=n_core, next=n_ext, nxe=n_xe))
    L.append("|---|---|---|---|---|---|")
    for i in impls:
        s = scores["implementations"][i]
        eb = s["extended_breadth"]
        xe = s.get("extended_experimental_breadth", {"supported": 0, "total": n_xe})
        core_pass = n_core - len(s["core_failed"])
        conf = (T["c_s1_pass"].format(cp=core_pass, n=n_core) if s["core_conformant"]
                else T["c_s1_fail"].format(cp=core_pass, n=n_core))
        failed = ", ".join(s["core_failed"]) or "-"
        L.append(f"| {i} | {s.get('version') or '-'} | {conf} | "
                 f"{eb['supported']}/{eb['total']} | {xe['supported']}/{xe['total']} | {failed} |")
    L.append("")
    L.append(T["c_s1_b1"])
    L.append(T["c_s1_b2"].format(nxe=n_xe))
    L.append(T["c_s1_b3"] + "\n")
    L.append(T["c_s1_version"] + "\n")

    # 2. 항목별 상세 (채점: Core + Extended 양 채널)
    graded = groups["core"] + groups["extended-standard"] + groups["extended-experimental"]
    L.append(T["c_s2_h"].format(tot=n_core + n_ext + n_xe, ncore=n_core, next=n_ext, nxe=n_xe) + "\n")
    L.append(f"| {T['c_s2_col_test']} | {T['c_s2_col_cat']} | " + " | ".join(impls) + " |")
    L.append("|" + "---|" * (2 + len(impls)))
    lv_label = {"core": T["c_lv_core"], "extended-standard": T["c_lv_extstd"],
                "extended-experimental": T["c_lv_extexp"]}
    for t in graded:
        meta = rubric["tests"][t]
        lv = lv_label.get(meta["level"], meta["level"])
        diff = meta.get("differentiation")
        dmark = {"common": T["c_diff_common"], "differentiating": T["c_diff_diff"]}.get(diff, "")
        cells = []
        for i in impls:
            ta = agg["implementations"].get(i, {}).get("tests", {}).get(t)
            if t == CANARY_TEST:
                cells.append(_canary_cell(ta))
            else:
                cells.append(_state_mark(_detail_state(ta), lang))
        label = f"[{t}](#canary-detail)" if t == CANARY_TEST else t
        L.append(f"| {label}{dmark} | {lv} | " + " | ".join(cells) + " |")
    L.append("")
    L.append(T["c_s2_b1"])
    L.append(T["c_s2_b2"] + "\n")

    # 3. canary 품질 지표
    L.append('<a id="canary-detail"></a>')
    L.append(T["c_s3_h"] + "\n")
    L.append(T["c_s3_cols"])
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
        # canary_source.note는 데이터(aggregated.json)에 한국어로 박혀 있다(데이터 불변).
        # 영어 리포트에선 알려진 원문만 표시용으로 번역하고, 미지의 값은 원문 그대로 둔다.
        note = cs['note']
        if lang == "en":
            note = _CANARY_NOTE_EN.get(note, note)
        L.append(T["c_s3_source"].format(note=note))
    L.append(T["c_s3_b1"])
    L.append(T["c_s3_b2"] + "\n")

    # 4. experimental 필드
    exp = [t for t in groups["experimental"] if not t.startswith("auth")]
    L.append(T["c_s4_h"] + "\n")
    L.append(T["c_s4_note"] + "\n")
    L.append("| " + T["m_s2_col_impl"] + " | " + " | ".join(exp) + " |")
    L.append("|" + "---|" * (1 + len(exp)))
    for i in impls:
        s = scores["implementations"][i]["experimental"]
        cells = [_state_mark(s.get(t, "no-data"), lang) for t in exp]
        L.append(f"| {i} | " + " | ".join(cells) + " |")
    L.append("")
    # retry 상세
    rt = []
    for i in impls:
        st = scores["implementations"][i]["experimental"].get("retry")
        ta = agg["implementations"].get(i, {}).get("tests", {}).get("retry") or {}
        att = (ta.get("sample_metadata") or {}).get("upstream_attempts")
        infra = (ta.get("counts") or {}).get("infra-excluded", 0)
        if st == "pass":
            v = T["c_s4_retry_pass_n"].format(i=i, n=att) if att else T["c_s4_retry_pass"].format(i=i)
            if infra:
                v += T["c_s4_retry_infra"]
            rt.append(v)
        elif st in ("unsupported", "fail"):
            rt.append(T["c_s4_retry_unsup"].format(i=i))
    if rt:
        L.append(T["c_s4_retry_note"].format(body=", ".join(rt)) + "\n")

    # 매트릭스 셀 렌더 헬퍼
    def _matrix_cells(item_list):
        rows = []
        for i in impls:
            m = scores["implementations"][i]["impl_matrix"]
            cells = []
            for t in item_list:
                entry = m.get(t, {})
                mv = entry.get("matrix") or {}
                label = mv.get("matrix_value") or _state_mark(entry.get("state"), lang)
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
    L.append(T["c_s5_h"] + "\n")
    L.append(T["c_s5_note"] + "\n")
    L.append("| " + T["m_s2_col_impl"] + " | " + " | ".join(vendor_items) + " |")
    L.append("|" + "---|" * (1 + len(vendor_items)))
    L += _matrix_cells(vendor_items)
    L.append("")
    L.append(T["c_s5_fairness"] + "\n")

    # 6. 비기능 / 운영 지표
    nonfunc_items = (["health-check"] if "health-check" in groups["impl-specific"] else []) \
        + groups["non-functional"]
    L.append(T["c_s6_h"] + "\n")
    L.append("| " + T["m_s2_col_impl"] + " | " + " | ".join(nonfunc_items) + " |")
    L.append("|" + "---|" * (1 + len(nonfunc_items)))
    L += _matrix_cells(nonfunc_items)
    L.append("")
    # failover-recovery 복구 상세
    fo = []
    for i in impls:
        st = scores["implementations"][i]["impl_matrix"].get("failover-recovery", {}).get("state")
        ta = agg["implementations"].get(i, {}).get("tests", {}).get("failover-recovery") or {}
        meta = ta.get("sample_metadata") or {}
        rs = meta.get("recovery_s")
        if st == "pass" and rs is not None:
            fo.append(T["c_fo_zero"].format(i=i) if rs == 0 else T["c_fo_recover"].format(i=i, rs=rs))
        elif st == "unsupported":
            fo.append(T["c_fo_excl"].format(i=i))
    if fo:
        L.append(T["c_fo_note"].format(body=", ".join(fo)) + "\n")
    # health-check 상세
    hc = []
    for i in impls:
        st = scores["implementations"][i]["impl_matrix"].get("health-check", {}).get("state")
        if st == "pass":
            hc.append(T["c_hc_sup"].format(i=i))
        elif st == "unsupported":
            hc.append(T["c_hc_unsup"].format(i=i))
    if hc:
        L.append(T["c_hc_note"].format(body=", ".join(hc)) + "\n")
    # config-robustness 측정 조건/뉘앙스
    if any("config-robustness" in scores["implementations"][i].get("impl_matrix", {}) for i in impls):
        L.append(T["c_cr_note"] + "\n")

    # 7. auth
    L.append(T["c_s7_h"] + "\n")
    L.append(T["c_s7_note"] + "\n")
    L.append(T["c_s7_cols"])
    L.append("|---|---|---|---|")
    for i in impls:
        a = AUTH.get(i, ("-", "-", "-"))
        L.append(f"| {i} | {_auth_label(a[0], lang)} | {_auth_label(a[1], lang)} | {_auth_label(a[2], lang)} |")
    L.append("")
    L.append(T["c_s7_b"] + "\n")

    # 8. 플레이크
    flaky = {i: [t for t in s["flaky_tests"] if t != CANARY_TEST]
             for i, s in scores["implementations"].items()
             if [t for t in s.get("flaky_tests", []) if t != CANARY_TEST]}
    L.append(T["c_s8_h"] + "\n")
    if flaky:
        for i, ts in flaky.items():
            parts = []
            for t in ts:
                ta = agg["implementations"].get(i, {}).get("tests", {}).get(t, {})
                pr = ta.get("pass_rate")
                parts.append(f"{t}({pr*100:.1f}%)" if pr is not None else t)
            L.append(T["c_s8_row"].format(i=i, parts=', '.join(parts)))
    else:
        L.append(T["c_s8_none"])
    L.append("")

    # 9. not-configured
    notcfg = {i: list(s.get("data_errors", {}).keys())
              for i, s in scores["implementations"].items() if s.get("data_errors")}
    if notcfg:
        L.append(T["c_s9_h"] + "\n")
        L.append(T["c_s9_note"] + "\n")
        for i, ts in notcfg.items():
            auth = sorted(t for t in ts if t.startswith("auth"))
            gap = sorted(t for t in ts if not t.startswith("auth"))
            parts = []
            if auth:
                parts.append(T["c_s9_done"].format(items=', '.join(auth)))
            if gap:
                parts.append(T["c_s9_gap"].format(items=', '.join(gap)))
            L.append(f"- {i}: " + " | ".join(parts))
        L.append("")

    return "\n".join(L)


# ===========================================================================
# 출발점 뷰 (migration)
# ===========================================================================
_TIER_ORDER = ["standard", "caution", "vendor", "blocked"]
_I2GW = {"converts": "✓", "partial": "~", "no": "✗", "n-a": "native"}
# 커버리지 요약에서 "지원(동작)"으로 셀 수 있는 auth 텍스트(저수준 포함). AUTH 토큰 기준.
_AUTH_COVERED = {
    "native-jwks": True, "plus-only-basic": False, "kgo-secret-deny": False,
    "securitypolicy": True, "authzpolicy-custom": True, "forwardauth-native": True,
    "gatewayextension": True, "snippetsfilter-low": True, "oss-unsupported": False, "unsupported": False,
}


def _mig_cell(agg: dict, scores: dict, impl: str, t: str | None, lang: str) -> str:
    """출발점 점검표의 구현체별 셀. maps_to에 따라 실측/매트릭스/auth/구조 분기.
    auth 셀은 토큰을 반환(커버리지 계산은 토큰으로). 표시 변환은 _mig_display가 한다."""
    if t is None:
        return "(not measured)" if lang == "en" else "(미측정)"
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
        return mv.get("matrix_value") or _state_mark(entry.get("state"), lang)
    if t in s.get("experimental", {}):
        return _state_mark(s["experimental"][t], lang)
    ta = agg["implementations"].get(impl, {}).get("tests", {}).get(t)
    return _state_mark(_detail_state(ta), lang)


def _mig_display(agg: dict, scores: dict, impl: str, t: str | None, lang: str) -> str:
    """표 셀 표시값. auth(maps_to=auth-*)면 토큰을 언어별 라벨로 변환."""
    cell = _mig_cell(agg, scores, impl, t, lang)
    if t in ("auth-jwt", "auth-extauth"):
        return _auth_label(cell, lang)
    return cell


def _mig_covered(cell: str) -> bool:
    """커버리지 요약용: 셀이 '동작(저수준 포함)'이면 True. cell은 _mig_cell의 raw 토큰/값."""
    if cell == "PASS":
        return True
    if cell in ("FAIL", "n/a", "-", "(미측정)", "(not measured)", "no-data", "unsupported",
                "overmatch", "미구성", "not-configured"):
        return False
    if cell in ("native", "low-level-config", "supported", "robust"):
        return True
    return _AUTH_COVERED.get(cell, False)


def build_migration_markdown(agg: dict, scores: dict, rubric: dict, lang: str = "en") -> str:
    T = TXT[lang]
    mv = rubric["migration_view"]
    caps = mv["capabilities"]
    tiers = mv["tiers"]
    impls = list(scores["implementations"].keys())

    def tier_name(k):
        return tiers[k].get("name_en", tiers[k]["name"]) if lang == "en" else tiers[k]["name"]

    def tier_desc(k):
        return tiers[k].get("desc_en", tiers[k]["desc"]) if lang == "en" else tiers[k]["desc"]

    def cap_field(c, base):
        return c.get(base + "_en", c[base]) if (lang == "en" and (base + "_en") in c) else c.get(base)

    L = []
    gwv = mv['meta']['gateway_api_version']
    i2gw = mv['meta']['i2gw_version']
    headline = mv['meta'].get('headline_en', mv['meta']['headline']) if lang == "en" else mv['meta']['headline']
    L.append("# " + T["m_title"].format(gwv=gwv) + "\n")
    L.append(f"> **{headline}**\n")
    L.append(T["m_lens"] + "\n")
    L.append(T["m_basis"].format(gwv=gwv, i2gw=i2gw) + "\n")

    # 1. 난이도 4등급
    L.append(T["m_s1_h"] + "\n")
    L.append(T["m_s1_cols"])
    L.append("|---|---|")
    for k in _TIER_ORDER:
        L.append(f"| **{tier_name(k)}** | {tier_desc(k)} |")
    L.append("")

    # 2. 구현체별 커버리지
    L.append(T["m_s2_h"] + "\n")
    L.append(T["m_s2_note"] + "\n")
    measurable = {k: [c for c in caps if c["tier"] == k and c["maps_to"]] for k in _TIER_ORDER}
    short = T["m_tier_short"]
    head = [T["m_s2_col_impl"]] + [f"{tier_name(k).split(' ')[0]} {short.get(k, k)}({len(measurable[k])})"
                                   for k in _TIER_ORDER if measurable[k]] + [T["m_s2_total"]]
    L.append("| " + " | ".join(head) + " |")
    L.append("|" + "---|" * len(head))
    for i in impls:
        cells = []
        tot_ok = tot_n = 0
        for k in _TIER_ORDER:
            if not measurable[k]:
                continue
            ok = sum(_mig_covered(_mig_cell(agg, scores, i, c["maps_to"], lang)) for c in measurable[k])
            n = len(measurable[k])
            cells.append(f"{ok}/{n}")
            tot_ok += ok
            tot_n += n
        L.append(f"| {i} | " + " | ".join(cells) + f" | **{tot_ok}/{tot_n}** |")
    L.append("")
    L.append(T["m_s2_b"] + "\n")

    # 3. 마이그레이션 점검표 (난이도 그룹)
    L.append(T["m_s3_h"].format(n=len(caps)) + "\n")
    L.append(T["m_s3_legend"].format(i2gw=i2gw) + "\n")
    tier_counts = {k: sum(1 for c in caps if c["tier"] == k) for k in _TIER_ORDER}
    for k in _TIER_ORDER:
        group = [c for c in caps if c["tier"] == k]
        L.append(f"### {tier_name(k)} ({tier_counts[k]})\n")
        L.append(T["m_s3_grade_cols"] + " | ".join(impls) + " |")
        L.append("|" + "---|" * (5 + len(impls)))
        notes = []
        for c in group:
            cells = [_mig_display(agg, scores, i, c["maps_to"], lang) for i in impls]
            if c["maps_to"] is None and c.get("structural_cell"):
                cells = [c["structural_cell"]] * len(impls)
            imp = {"high": T["m_imp_high"], "medium": T["m_imp_medium"],
                   "low": T["m_imp_low"]}.get(c["importance"], c["importance"])
            i2 = _I2GW.get(c["i2gw"], c["i2gw"])
            capname = cap_field(c, "capability")
            nref = ""
            note = cap_field(c, "note") if cap_field(c, "note") else None
            if note:
                notes.append(f"  - **{capname}**: {note}")
                nref = " ※"
            gw_status = cap_field(c, "gw_status")
            L.append(f"| {capname}{nref} | `{cap_field(c, 'annotation')}` | {imp} | "
                     f"{gw_status} | {i2} | " + " | ".join(cells) + " |")
        L.append("")
        if notes:
            L.append(T["m_s3_notes_h"])
            L += notes
            L.append("")

    # 4. 차별점, 출처, 한계
    L.append(T["m_s4_h"] + "\n")
    L.append(T["m_s4_l1"])
    L.append(T["m_s4_l2"].format(i2gw=i2gw))
    L.append(T["m_s4_l3"])
    L.append(T["m_s4_l4"])
    L.append(T["m_s4_l5"])
    L.append(T["m_s4_l6"] + "\n")
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
    "FAIL": "bad", "FLAKY": "warn", "미구성": "warn", "not-configured": "warn",
    "n/a": "muted", "unsupported": "muted", "미지원": "muted", "-": "muted",
    "(미측정)": "muted", "(not measured)": "muted", "no-data": "muted",
    "overmatch": "warn", "low-level-config": "warn",
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


def _conformance_summary_html(scores: dict, lang: str = "en") -> str:
    T = TXT[lang]
    rows = [T["c_sum_cols"]]
    for i, s in scores["implementations"].items():
        eb = s["extended_breadth"]
        n_core = s.get("core_total", 7)
        core_pass = s.get("core_passed", n_core - len(s["core_failed"]))
        conf = (T["c_sum_pass"].format(cp=core_pass, n=n_core) if s["core_conformant"]
                else T["c_sum_fail"].format(cp=core_pass, n=n_core))
        cls = "ok" if s["core_conformant"] else "bad"
        rows.append(f"<tr><td>{i}</td><td class='{cls}'>{conf}</td>"
                    f"<td>{eb['supported']}/{eb['total']}</td>"
                    f"<td>{', '.join(s['core_failed']) or '-'}</td></tr>")
    rows.append("</table>")
    rows.append(T["c_sum_foot"])
    return "".join(rows)


def _migration_summary_html(agg: dict, scores: dict, rubric: dict, lang: str = "en") -> str:
    T = TXT[lang]
    caps = rubric["migration_view"]["capabilities"]
    impls = list(scores["implementations"].keys())
    measurable = {k: [c for c in caps if c["tier"] == k and c["maps_to"]]
                  for k in _TIER_ORDER}
    rows = [T["m_sum_cols"]]
    for i in impls:
        tds = []
        tot_ok = tot_n = 0
        for k in ("standard", "caution", "vendor"):
            ok = sum(_mig_covered(_mig_cell(agg, scores, i, c["maps_to"], lang)) for c in measurable[k])
            n = len(measurable[k])
            tds.append(f"<td>{ok}/{n}</td>")
            tot_ok += ok
            tot_n += n
        rows.append(f"<tr><td>{i}</td>" + "".join(tds) + f"<td><b>{tot_ok}/{tot_n}</b></td></tr>")
    rows.append("</table>")
    rows.append(T["m_sum_foot"])
    return "".join(rows)


def build_html(title: str, summary_html: str, md: str, lang: str = "en") -> str:
    # md 첫 헤딩(# 제목)을 떼어 맨 위에, 그 다음 요약표, 그 다음 본문 순서로 배치.
    glance = TXT[lang]["at_a_glance"]
    lines = md.split("\n")
    head, rest = "", md
    for idx, ln in enumerate(lines):
        if ln.strip().startswith("# "):
            head = _md_to_html(ln.strip())
            rest = "\n".join(lines[:idx] + lines[idx + 1:])
            break
    return (f"<!doctype html><meta charset=utf-8><title>{title}</title><style>{_CSS}</style>"
            + head
            + f'<div class="summary"><h2>{glance}</h2>' + summary_html + "</div>\n"
            + _md_to_html(rest))


# 언어별 출력 파일명. en=기본(접미사 없음), ko=_ko 접미사.
_LANG_SUFFIX = {"en": "", "ko": "_ko"}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--agg", default=str(GW / "results" / "aggregated.json"))
    ap.add_argument("--scores", default=str(GW / "results" / "scores.json"))
    ap.add_argument("--rubric", default=str(GW / "rubric.yaml"))
    ap.add_argument("--outdir", default=str(GW / "metrics"))
    ap.add_argument("--view", choices=["conformance", "migration", "both"], default="both")
    ap.add_argument("--lang", choices=["en", "ko", "both"], default="both")
    args = ap.parse_args()

    with open(args.agg) as f:
        agg = json.load(f)
    with open(args.scores) as f:
        scores = json.load(f)
    rubric = gwlib.load_rubric(Path(args.rubric))
    base = Path(args.outdir)

    views = ["conformance", "migration"] if args.view == "both" else [args.view]
    langs = ["en", "ko"] if args.lang == "both" else [args.lang]
    for v in views:
        out = base / f"{v}-view"
        out.mkdir(parents=True, exist_ok=True)
        for lang in langs:
            T = TXT[lang]
            if v == "conformance":
                md = build_conformance_markdown(agg, scores, rubric, lang)
                html = build_html(T["html_title_conf"],
                                  _conformance_summary_html(scores, lang), md, lang)
            else:
                md = build_migration_markdown(agg, scores, rubric, lang)
                html = build_html(T["html_title_mig"],
                                  _migration_summary_html(agg, scores, rubric, lang), md, lang)
            sfx = _LANG_SUFFIX[lang]
            md_path = out / f"README_tables{sfx}.md"
            html_path = out / f"report{sfx}.html"
            md_path.write_text(md)
            html_path.write_text(html)
            print(f"{v} [{lang}] → {html_path}, {md_path}")


if __name__ == "__main__":
    main()
