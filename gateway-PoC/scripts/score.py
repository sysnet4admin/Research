#!/usr/bin/env python3
"""score.py: aggregated.json + rubric.yaml → scores.json (3축)

3축(SCORING.md 2.1):
  - Core 적합성: 7개 Core 전부 supported → Conformant
  - Extended 폭: 지원 Extended-standard 수 / 13 (v3 확장 후 5→13)
  - 실험 역량: retry, session-affinity 등 (등급 미반영, 보고)
  - Impl 매트릭스: 비표준 항목 (등급 미반영, 보고)

"supported" 정의(확정): pass_rate == 1.0 (전 라운드 통과). Core 100% 요구와
동일 기준을 Extended 지원 판정에도 적용. 실제 통과율/분산은 리포트에 그대로 표기.

사용: python3 score.py [--agg FILE] [--rubric FILE] [--out FILE]
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path

import gwlib

HERE = Path(__file__).resolve().parent
GW = HERE.parent

SUPPORTED_THRESHOLD = 1.0   # 확정: 전 라운드 통과해야 supported(결정론 항목)
CANARY_TEST = "canary-traffic"


def _supported(test_agg: dict) -> bool:
    pr = test_agg.get("pass_rate")
    return pr is not None and pr >= SUPPORTED_THRESHOLD


def _is_no_data(test_agg: dict | None) -> bool:
    """측정 데이터 없음(전부 infra-excluded/not-configured 등). 측정상 실패와 구분.
    인프라 제외 정책상 no-data는 '재측정 대상'이지 비적합/미지원이 아니다."""
    if not test_agg:
        return True
    return test_agg.get("valid_rounds", 0) == 0 or test_agg.get("pass_rate") is None


def _core_supported(name: str, test_agg: dict) -> bool:
    """Core 지원 판정. 결정론 항목은 전 라운드 통과(pass_rate==1.0).
    canary(표본 테스트)는 라운드별 100%가 아니라 누적 풀링 split이 목표(80/20)에
    2-sigma 내로 수렴하면 supported(통계적으로 옳은 집계). 라운드별 노이즈는 품질
    지표로 별도 보고. 두 방식 모두 7종 결론 동일하나, 풀링이 표본 테스트엔 정확."""
    if name == CANARY_TEST:
        pool = test_agg.get("canary_pool")
        if pool is not None and pool.get("within_2sigma") is not None:
            return bool(pool["within_2sigma"])
        # 풀 데이터 없으면 보수적으로 결정론 기준 적용
    return _supported(test_agg)


def _state(test_agg: dict | None) -> str:
    """리포트용 상태 문자열."""
    if test_agg is None or test_agg.get("valid_rounds", 0) == 0:
        # 하네스 미구성(not-configured)은 계측 공백으로 구분(설계상 미지원 아님).
        if test_agg and (test_agg.get("counts") or {}).get("not-configured", 0) > 0:
            return "not-configured"
        return "no-data"
    pr = test_agg["pass_rate"]
    if pr is None:
        return "no-data"
    if pr >= 1.0:
        return "pass"
    if pr <= 0.0:
        return "unsupported"
    return "flaky"


def score(agg: dict, rubric: dict) -> dict:
    groups = gwlib.level_groups(rubric)
    core = groups["core"]
    ext = groups["extended-standard"]
    ext_exp = groups["extended-experimental"]
    experimental = groups["experimental"]
    impl_items = groups["impl-specific"] + groups["non-functional"]

    out: dict = {
        "gateway_api_version": agg.get("gateway_api_version"),
        "rounds": agg.get("rounds"),
        "supported_threshold": SUPPORTED_THRESHOLD,
        "implementations": {},
    }

    total_rounds = agg.get("rounds")
    for impl, block in agg["implementations"].items():
        tests = block["tests"]

        # no-data(측정 없음)는 측정상 실패(core_failed)와 분리한다. canary는 풀링 판정
        # 이라 no-data 판정에서 제외(valid_rounds=155이나 결정론 rounds와 다름).
        core_no_data = [t for t in core
                        if t != CANARY_TEST and _is_no_data(tests.get(t))]
        core_failed = [t for t in core if t not in core_no_data
                       and not _core_supported(t, tests.get(t, {}))]
        # 적합 = 미통과 0 그리고 no-data 0(측정 안 된 Core가 있으면 단정 불가).
        core_conformant = len(core_failed) == 0 and len(core_no_data) == 0
        # low-data 진단: 지원 판정이 결정론 라운드수보다 적은 유효표본에 기댄 경우
        # (예: 실패 라운드를 infra-excluded로 돌려 분모가 작아진 경우) 가시화. 등급 불변.
        low_data = []
        if isinstance(total_rounds, int):
            for t in core + ext + ext_exp:
                if t == CANARY_TEST:
                    continue
                vr = (tests.get(t) or {}).get("valid_rounds", 0)
                if 0 < vr < total_rounds and _supported(tests.get(t, {})):
                    low_data.append(t)

        ext_supported = [t for t in ext if _supported(tests.get(t, {}))]
        ext_unsupported = [t for t in ext if not _supported(tests.get(t, {}))]
        # experimental 채널 Extended(conformance 기능 보유, 별도 graded 축)
        xe_supported = [t for t in ext_exp if _supported(tests.get(t, {}))]
        xe_unsupported = [t for t in ext_exp if not _supported(tests.get(t, {}))]

        out["implementations"][impl] = {
            "version": block.get("version"),
            "core_conformant": core_conformant,
            "core_total": len(core),
            "core_passed": len(core) - len(core_failed) - len(core_no_data),
            "core_failed": core_failed,
            "core_no_data": core_no_data,
            "low_data_tests": low_data,
            # canary 품질 지표(풀링 split + 라운드별 분산). 보고서/blog/발표용 보존.
            "canary_quality": tests.get(CANARY_TEST, {}).get("canary_pool"),
            "extended_breadth": {
                "supported": len(ext_supported),
                "total": len(ext),
                "ratio": round(len(ext_supported) / len(ext), 4) if ext else None,
                "supported_features": ext_supported,
                "unsupported_features": ext_unsupported,
            },
            "extended_experimental_breadth": {
                "supported": len(xe_supported),
                "total": len(ext_exp),
                "supported_features": xe_supported,
                "unsupported_features": xe_unsupported,
            },
            "experimental": {
                t: _state(tests.get(t)) for t in experimental
            },
            "impl_matrix": {
                t: {
                    "state": _state(tests.get(t)),
                    "matrix": (tests.get(t, {}).get("sample_metadata") or {}),
                } for t in impl_items
            },
            "flaky_tests": [t for t, ta in tests.items() if ta.get("flaky")],
            "data_errors": {t: ta["data_errors"] for t, ta in tests.items()
                            if ta.get("data_errors")},
        }
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--agg", default=str(GW / "results" / "aggregated.json"))
    ap.add_argument("--rubric", default=str(GW / "rubric.yaml"))
    ap.add_argument("--out", default=str(GW / "results" / "scores.json"))
    args = ap.parse_args()

    with open(args.agg) as f:
        agg = json.load(f)
    rubric = gwlib.load_rubric(Path(args.rubric))
    sc = score(agg, rubric)
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    with open(args.out, "w") as f:
        json.dump(sc, f, indent=2, ensure_ascii=False)

    conformant = [i for i, s in sc["implementations"].items() if s["core_conformant"]]
    print(f"scored {len(sc['implementations'])} impls → {args.out}")
    print(f"  Core conformant: {', '.join(conformant) or '(none)'}")


if __name__ == "__main__":
    main()
