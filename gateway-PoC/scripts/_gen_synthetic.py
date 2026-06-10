#!/usr/bin/env python3
"""합성 round-N.json 생성기 (scoring 파이프라인 오프라인 검증 전용).

실제 측정 산출이 아니라, score/aggregate/report 코드 경로를 검증하기 위한
그럴듯한 가짜 데이터다. 플레이크/인프라제외/데이터오류 경로를 일부러 넣는다.
실제 측정 스크립트(측정 단계)가 이 스키마로 round-N.json을 만든다.

오염 방지: 기본 출력은 실제 라운드 디렉토리(results/rounds)가 아니라 격리된
results/_synthetic 이며, 각 라운드에 "synthetic": true 마커를 박는다(gwlib.load_rounds
가 이 마커를 보면 경고). 실제 파이프라인에 섞으려면 명시적으로 --out 으로 실제
디렉토리를 지정해야 하고, 그래도 마커 때문에 집계 시 경고가 뜬다.
"""
from __future__ import annotations
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

GW = Path(__file__).resolve().parent.parent
ROUNDS = GW / "results" / "_synthetic"   # 실제 results/rounds 와 분리(오염 방지)

CORE = ["host-routing", "path-routing", "header-routing", "tls-termination",
        "canary-traffic", "header-modifier", "cross-namespace"]
EXT = ["https-redirect", "url-rewrite", "timeout", "backend-tls", "grpc-routing"]
EXPER = ["retry", "session-affinity"]
IMPL = ["rate-limiting", "health-check", "load-test", "failover-recovery"]
ALL = CORE + EXT + EXPER + IMPL

P, F, U = "pass", "fail", ("skip", "unsupported")

# 구현체별 기본 프로파일(2026-06 그럴듯). 명시 안 한 core는 pass.
PROFILE = {
    "nginx":   {"version": "2.4.2", "ip": "192.168.1.11",
                "timeout": U, "retry": U, "session-affinity": U,
                "rate-limiting": ("pass", {"matrix_value": "low-level-config"})},
    "envoy":   {"version": "v1.7.3", "ip": "192.168.1.12",
                "rate-limiting": ("pass", {"matrix_value": "native"})},
    "istio":   {"version": "1.30.0", "ip": "192.168.1.14",
                "backend-tls": U, "retry": U, "session-affinity": U,
                "rate-limiting": ("pass", {"matrix_value": "low-level-config"})},
    "cilium":  {"version": "1.19.4", "ip": "192.168.1.15",
                "retry": U, "session-affinity": U,
                "rate-limiting": ("skip", "unsupported")},
    "kong":    {"version": "KGO 2.1.6", "ip": "192.168.1.16",
                "canary-traffic": F,   # HTTPRouteWeight → core fail (non-conformant)
                "https-redirect": U, "timeout": U, "backend-tls": U,
                "grpc-routing": U, "retry": U, "session-affinity": U,
                "rate-limiting": ("pass", {"matrix_value": "native"})},
    "traefik": {"version": "v3.6.17", "ip": "192.168.1.17",
                "timeout": U, "retry": U, "session-affinity": U,
                "rate-limiting": ("pass", {"matrix_value": "native"})},
    "kgateway": {"version": "v2.2.2", "ip": "192.168.1.13",
                 "session-affinity": U,
                 "rate-limiting": ("pass", {"matrix_value": "native"})},
}
GCLASS = {"nginx": "nginx", "envoy": "eg", "istio": "istio", "cilium": "cilium",
          "kong": "kong", "traefik": "traefik", "kgateway": "kgateway"}


def cell(impl: str, test: str, rnd: int):
    """(result, skip_code, metadata) 반환. 라운드별 변형(플레이크 등) 주입."""
    prof = PROFILE[impl]
    # 라운드 변형 주입
    if impl == "kgateway" and test == "load-test" and rnd == 3:
        return "fail", None, {}          # 플레이크
    if impl == "cilium" and test == "backend-tls" and rnd == 2:
        return "skip", "infra-excluded", {}   # 인프라 제외(분모 제외)
    if impl == "kong" and test == "backend-tls" and rnd == 1:
        return "skip", "not-configured", {}   # 데이터 오류 플래그

    spec = prof.get(test)
    if spec is None:
        return "pass", None, {}
    if spec == F:
        return "fail", None, {}
    if isinstance(spec, tuple) and spec[0] == "skip":
        return "skip", spec[1], {}
    if isinstance(spec, tuple) and spec[0] == "pass":
        return "pass", None, spec[1]
    return "pass", None, {}


def make_round(rnd: int) -> dict:
    impls = []
    for impl, prof in PROFILE.items():
        tests = []
        for t in ALL:
            res, skip, meta = cell(impl, t, rnd)
            tests.append({"name": t, "result": res, "skip_code": skip,
                          "duration_ms": 100 + (hash((impl, t)) % 400),
                          "metadata": meta})
        impls.append({"implementation": impl, "gateway_class": GCLASS[impl],
                      "version": prof["version"], "gateway_ip": prof["ip"],
                      "tests": tests})
    return {"round": rnd, "timestamp": datetime.now(timezone.utc).isoformat(),
            "gateway_api_version": "v1.4", "crd_channel": "experimental",
            "architecture": "arm64", "synthetic": True, "implementations": impls}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROUNDS),
                    help="합성 라운드 출력 디렉토리(기본: 격리된 results/_synthetic)")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    for rnd in (1, 2, 3):
        p = out / f"round-{rnd}.json"
        with open(p, "w") as f:
            json.dump(make_round(rnd), f, indent=2, ensure_ascii=False)
        print("wrote", p)
    print(f"합성 데이터(synthetic:true 마커 포함). 검증: "
          f"python3 aggregate.py --rounds {out} --out /tmp/synth_agg.json")


if __name__ == "__main__":
    main()
