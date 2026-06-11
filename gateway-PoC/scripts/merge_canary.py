#!/usr/bin/env python3
"""merge_canary.py: 신규 v3 캠페인 aggregated + 기존 155라운드 canary 병합.

배경: graded Extended 확대(/13)와 매트릭스 실측화로 결정론 항목을 소수 라운드 재측정한다.
canary(가중 분배)는 표본 테스트라 다라운드 풀링이 필요하고, 발표 메트릭(79.4~80.0%)이
그대로 보존돼 있다. 따라서 결정론 항목은 신규 캠페인 값을, canary는 기존 155라운드 풀링값을 쓴다.

동작: 신규 aggregated의 각 impl `canary-traffic` 테스트 엔트리를 기존 aggregated 값으로 교체.
사용: merge_canary.py --new NEW_AGG --old OLD_AGG --out OUT
"""
import argparse
import json
from pathlib import Path

CANARY = "canary-traffic"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--new", required=True, help="신규 v3 캠페인 aggregated.json")
    ap.add_argument("--old", required=True, help="기존 155라운드 aggregated.json(canary 소스)")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    new = json.loads(Path(args.new).read_text())
    old = json.loads(Path(args.old).read_text())

    patched = 0
    for impl, idata in new["implementations"].items():
        old_impl = old["implementations"].get(impl, {})
        old_canary = old_impl.get("tests", {}).get(CANARY)
        if old_canary is not None:
            idata.setdefault("tests", {})[CANARY] = old_canary
            patched += 1

    # 메타: 결정론은 신규 라운드수, canary는 155라운드 풀링임을 명시
    new["canary_source"] = {
        "from": "frozen-155-round-pool",
        "rounds_sampled": old.get("rounds"),
        "note": "결정론 항목은 v3 캠페인 재측정, canary는 기존 155라운드 풀링 보존(발표 수치 고정)",
    }
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    Path(args.out).write_text(json.dumps(new, indent=2, ensure_ascii=False))
    print(f"merged canary for {patched} impls (deterministic={new.get('rounds')} rounds, "
          f"canary={old.get('rounds')}-round pool) → {args.out}")


if __name__ == "__main__":
    main()
