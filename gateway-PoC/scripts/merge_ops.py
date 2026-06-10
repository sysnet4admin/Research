#!/usr/bin/env python3
"""merge_ops.py — 격리 측정한 운영 테스트(failover-recovery 등) 결과를 aggregated.json에 병합.

배경: failover-recovery 같은 운영 테스트는 데이터플레인을 강제 재시작하므로 결정론/
canary 측정과 섞으면 다른 항목을 교란한다. 그래서 별도 캠페인(results/rounds-ops)에서
측정하고, 그 결과의 해당 테스트 엔트리만 메인 aggregated.json에 주입한다(canary 병합과
같은 분리-후-병합 패턴). 동결 graded/canary 항목은 건드리지 않는다.

사용: merge_ops.py --agg AGG --ops OPS_AGG --tests "failover-recovery" --out OUT
"""
import argparse
import json
from pathlib import Path


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--agg", required=True, help="메인 aggregated.json")
    ap.add_argument("--ops", required=True, help="rounds-ops aggregated.json")
    ap.add_argument("--tests", required=True, help="병합할 테스트명(공백 구분)")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    agg = json.loads(Path(args.agg).read_text())
    ops = json.loads(Path(args.ops).read_text())
    tests = args.tests.split()

    patched = 0
    for impl, idata in agg["implementations"].items():
        ops_tests = ops["implementations"].get(impl, {}).get("tests", {})
        for t in tests:
            entry = ops_tests.get(t)
            if entry is not None:
                idata.setdefault("tests", {})[t] = entry
                patched += 1

    # provenance는 병합마다 누적한다. finalize.sh가 이 스크립트를 캠페인별로
    # 여러 번 호출(rounds-ops, rounds-kong-expr, rounds-kgw-ba)하므로 단일 키에
    # 대입하면 마지막 병합만 남아 이전 캠페인 이력이 지워진다.
    agg.setdefault("ops_sources", []).append({
        "campaign": Path(args.ops).stem,
        "tests": tests,
        "rounds": ops.get("rounds"),
        "note": "결정론/canary와 분리된 격리 캠페인에서 측정 후 해당 테스트만 주입",
    })
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    Path(args.out).write_text(json.dumps(agg, indent=2, ensure_ascii=False))
    print(f"merged ops tests {tests}: {patched} entries "
          f"(ops={ops.get('rounds')} rounds) → {args.out}")


if __name__ == "__main__":
    main()
