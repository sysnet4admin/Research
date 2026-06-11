#!/usr/bin/env python3
"""aggregate.py: rounds/*.json → aggregated.json

항목별 라운드 통과율/분산을 계산한다(수작업 집계를 코드로 대체).
인프라 제외(infra-excluded) 라운드는 분모에서 제외(인프라 제외 정책).
하네스 미구성(not-configured)은 데이터 오류로 플래그.

사용: python3 aggregate.py [--rounds DIR] [--out FILE]
"""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path

import gwlib

# canary(가중 라우팅)는 표본 테스트라 라운드별 2-sigma 경계로는 정상이어도 약 5%가
# 벗어난다(노이즈). 다중 라운드를 누적 풀링해 split이 목표(80/20)에 수렴하는지로
# 판정하는 것이 통계적으로 옳다. 라운드별 분산은 품질 지표로 함께 보존(보고용).
CANARY_TEST = "canary-traffic"
CANARY_TARGET = 0.8                 # v1 가중치
# 라운드별 2-sigma 정수 구간(n=50, p=0.8): mean=40, sigma=2.8284, 2-sigma=[34.34,45.66].
# 그 안의 정수는 35..45. (34, 46은 2.12-sigma라 구간 밖). 보고용 이탈 카운트.
CANARY_ROUND_BOUNDS = (35, 45)

HERE = Path(__file__).resolve().parent
GW = HERE.parent


def _result_key(t: dict) -> str:
    """pass / fail / unsupported / not-configured / infra-excluded 로 정규화."""
    res = t.get("result")
    if res == gwlib.RESULT_SKIP:
        return t.get("skip_code") or gwlib.SKIP_UNSUPPORTED
    return res  # pass | fail


def aggregate(rounds: list[dict]) -> dict:
    impls = gwlib.implementations_in(rounds)
    out: dict = {
        "rounds": len(rounds),
        "gateway_api_version": rounds[0].get("gateway_api_version") if rounds else None,
        "crd_channel": rounds[0].get("crd_channel") if rounds else None,
        "implementations": {},
    }

    for impl in impls:
        per_test: dict[str, dict] = {}
        version = None
        for r in rounds:
            block = next((b for b in r["implementations"]
                          if b["implementation"] == impl), None)
            if block is None:
                continue
            version = version or block.get("version")
            for t in block.get("tests", []):
                name = t["name"]
                d = per_test.setdefault(name, {
                    "counts": {}, "sample_metadata": {}, "durations_ms": []})
                key = _result_key(t)
                d["counts"][key] = d["counts"].get(key, 0) + 1
                if t.get("metadata") and not d["sample_metadata"]:
                    d["sample_metadata"] = t["metadata"]
                if isinstance(t.get("duration_ms"), (int, float)):
                    d["durations_ms"].append(t["duration_ms"])
                # canary: 라운드별 v1/v2 표본을 모아 풀링/분산 산출
                if name == CANARY_TEST:
                    m = t.get("metadata") or {}
                    if "v1" in m:
                        d.setdefault("canary_v1", []).append(m["v1"])
                        d.setdefault("canary_v2", []).append(m.get("v2", 0))

        tests_out: dict[str, dict] = {}
        for name, d in per_test.items():
            c = d["counts"]
            n_pass = c.get(gwlib.RESULT_PASS, 0)
            n_fail = c.get(gwlib.RESULT_FAIL, 0)
            n_unsup = c.get(gwlib.SKIP_UNSUPPORTED, 0)
            n_notcfg = c.get(gwlib.SKIP_NOT_CONFIGURED, 0)
            n_infra = c.get(gwlib.SKIP_INFRA_EXCLUDED, 0)
            # 유효 분모: pass+fail+unsupported (infra-excluded, not-configured 제외)
            valid = n_pass + n_fail + n_unsup
            pass_rate = (n_pass / valid) if valid else None
            # 분산(베르누이): p(1-p)
            variance = (pass_rate * (1 - pass_rate)) if pass_rate is not None else None
            entry = {
                "counts": c,
                "valid_rounds": valid,
                "pass_rate": pass_rate,
                "variance": round(variance, 4) if variance is not None else None,
                "flaky": (pass_rate is not None and 0.0 < pass_rate < 1.0),
                "data_errors": ({"not-configured": n_notcfg} if n_notcfg else {}),
                "infra_excluded": n_infra,
                "sample_metadata": d["sample_metadata"],
            }
            # canary: 누적 풀링 split + 라운드별 분산(품질 지표, 보고용)
            if name == CANARY_TEST and d.get("canary_v1"):
                v1s = d["canary_v1"]
                v2s = d.get("canary_v2", [])
                V1, V2 = sum(v1s), sum(v2s)
                n = V1 + V2
                exp = CANARY_TARGET * n
                sigma = math.sqrt(n * CANARY_TARGET * (1 - CANARY_TARGET)) if n else 0.0
                lo, hi = CANARY_ROUND_BOUNDS
                entry["canary_pool"] = {
                    "v1_total": V1, "v2_total": V2, "samples": n,
                    "v1_ratio": round(V1 / n, 4) if n else None,
                    "target_ratio": CANARY_TARGET,
                    # 풀링 2-sigma: 누적 표본이 목표 split에 통계적으로 부합하는가
                    "within_2sigma": (abs(V1 - exp) <= 2 * sigma) if n else None,
                    "rounds_sampled": len(v1s),
                    # 라운드별 분산(보고용): 평균/최소/최대 v1, 2-sigma 이탈 라운드 수
                    "per_round_v1_mean": round(sum(v1s) / len(v1s), 2),
                    "per_round_v1_min": min(v1s),
                    "per_round_v1_max": max(v1s),
                    "per_round_excursions": sum(1 for x in v1s if not (lo <= x <= hi)),
                }
            tests_out[name] = entry
        out["implementations"][impl] = {"version": version, "tests": tests_out}
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--rounds", default=str(GW / "results" / "rounds"))
    ap.add_argument("--out", default=str(GW / "results" / "aggregated.json"))
    args = ap.parse_args()

    rounds = gwlib.load_rounds(Path(args.rounds))
    if not rounds:
        raise SystemExit(f"no round-*.json in {args.rounds}")
    agg = aggregate(rounds)
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    with open(args.out, "w") as f:
        json.dump(agg, f, indent=2, ensure_ascii=False)
    print(f"aggregated {agg['rounds']} rounds, "
          f"{len(agg['implementations'])} impls → {args.out}")


if __name__ == "__main__":
    main()
