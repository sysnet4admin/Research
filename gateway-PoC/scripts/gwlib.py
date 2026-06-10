"""Gateway PoC scoring 공유 라이브러리.

round-N.json(원시 측정) + rubric.yaml(동결 채점 계약)을 로드하고
레벨 그룹을 도출한다. aggregate/score/report 가 공유한다.

round-N.json 스키마:
{
  "round": 1,
  "timestamp": "2026-06-01T10:00:00Z",
  "gateway_api_version": "v1.4",
  "crd_channel": "experimental",
  "architecture": "arm64",
  "implementations": [
    {
      "implementation": "nginx",
      "gateway_class": "nginx",
      "version": "2.4.2",
      "gateway_ip": "192.168.1.11",   # 동적 발견(하드코딩 아님)
      "tests": [
        {"name": "host-routing", "result": "pass|fail|skip",
         "skip_code": "unsupported|not-configured|infra-excluded|null",
         "duration_ms": 120, "metadata": {}}
      ]
    }
  ]
}
"""
from __future__ import annotations
import json
from pathlib import Path

import yaml

RESULT_PASS = "pass"
RESULT_FAIL = "fail"
RESULT_SKIP = "skip"

SKIP_UNSUPPORTED = "unsupported"
SKIP_NOT_CONFIGURED = "not-configured"
SKIP_INFRA_EXCLUDED = "infra-excluded"


def load_rubric(path: Path) -> dict:
    with open(path) as f:
        return yaml.safe_load(f)


def level_groups(rubric: dict) -> dict[str, list[str]]:
    """rubric의 tests를 레벨별로 분류한다."""
    tests = rubric["tests"]
    g = {"core": [], "extended-standard": [], "extended-experimental": [],
         "experimental": [], "impl-specific": [], "non-functional": []}
    for name, t in tests.items():
        lv = t.get("level")
        if lv in g:
            g[lv].append(name)
    return g


def load_rounds(rounds_dir: Path) -> list[dict]:
    import sys
    rounds = []
    for p in sorted(rounds_dir.glob("round-*.json")):
        with open(p) as f:
            r = json.load(f)
        # 오염 방지: 합성 데이터(_gen_synthetic.py 마커)가 실제 집계에 섞이면 경고.
        if r.get("synthetic"):
            print(f"경고: 합성 라운드 파일 로드됨(synthetic:true): {p}. "
                  "실제 측정이 아니다. 의도한 검증이 아니면 분리할 것.", file=sys.stderr)
        rounds.append(r)
    return rounds


def implementations_in(rounds: list[dict]) -> list[str]:
    seen = []
    for r in rounds:
        for impl in r.get("implementations", []):
            name = impl["implementation"]
            if name not in seen:
                seen.append(name)
    return seen
