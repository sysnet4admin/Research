#!/usr/bin/env python3
"""ingress2gateway 변환 실측 + before/after manifest 보존.

각 ingress-nginx 어노테이션별로 샘플 Ingress(before)를 만들고 ingress2gateway를
실행해 변환 결과(after) + 통지(log)를 저장하고, 변환 여부를 분류한다.

분류:
  native   = 어노테이션 없는 기본 Ingress 필드(host/path/tls/websocket). 기본 변환됨.
  converts = 어노테이션이 Gateway API 등가물로 변환됨(unsupported 통지 없음).
  partial  = 변환되나 INFO/WARN 주의(의미 차이/best-effort).
  no       = "Unsupported annotation" 통지 = 미변환.

재현: python3 verify.py  (ingress2gateway 1.1.0 필요: brew install ingress2gateway)
"""
import json, re, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ING, GW, LOG = HERE / "ingress", HERE / "gateway", HERE / "logs"
for d in (ING, GW, LOG):
    d.mkdir(parents=True, exist_ok=True)

P = "nginx.ingress.kubernetes.io/"

# capability -> 샘플 정의. ann=어노테이션(prefix 자동), 그 외 spec 특이사항 플래그.
SAMPLES = {
    # 🟢 native 기본 필드
    "host-routing":   {"ann": {}, "hosts2": True},
    "path-routing":   {"ann": {}, "paths2": True},
    "tls-termination":{"ann": {}, "tls": True},
    "websocket":      {"ann": {}},  # ingress-nginx는 websocket 자동(어노테이션 없음)
    # 🟢 어노테이션
    "header-routing": {"ann": {"canary": "true", "canary-by-header": "X-Canary"}, "canary_pair": True},
    "https-redirect": {"ann": {"ssl-redirect": "true", "force-ssl-redirect": "true"}},
    "path-redirect":  {"ann": {"permanent-redirect": "https://new.example.com/"}},
    "url-rewrite":    {"ann": {"rewrite-target": "/new"}, "path": "/old"},
    "canary":         {"ann": {"canary": "true", "canary-weight": "20"}, "canary_pair": True},
    "request-mirror": {"ann": {"mirror-target": "http://mirror.example.com/"}},
    "header-modifier":{"ann": {"x-forwarded-prefix": "/app"}},
    # 🟡
    "regex":          {"ann": {"use-regex": "true"}, "path": "/api/v[0-9]+"},
    "timeout":        {"ann": {"proxy-connect-timeout": "10", "proxy-read-timeout": "60", "proxy-send-timeout": "60"}},
    "cors":           {"ann": {"enable-cors": "true", "cors-allow-origin": "https://x.example.com",
                               "cors-allow-methods": "GET, POST", "cors-allow-headers": "X-Custom"}},
    "external-auth":  {"ann": {"auth-url": "http://auth.example.com/check",
                               "auth-signin": "https://auth.example.com/start"}},
    "backend-tls":    {"ann": {"backend-protocol": "HTTPS"}},
    "grpc":           {"ann": {"backend-protocol": "GRPC"}},
    "tls-passthrough":{"ann": {"ssl-passthrough": "true"}, "tls": True},
    "mtls-client":    {"ann": {"auth-tls-secret": "default/ca-secret",
                               "auth-tls-verify-client": "on",
                               "auth-tls-verify-depth": "1"}, "tls": True},
    # 🟠
    "rate-limit":     {"ann": {"limit-rps": "5"}},
    "body-size":      {"ann": {"proxy-body-size": "8m"}},
    "session-affinity":{"ann": {"affinity": "cookie", "session-cookie-name": "route",
                                "session-cookie-expires": "172800"}},
    "ip-allow-deny":  {"ann": {"whitelist-source-range": "10.0.0.0/8,192.168.1.0/24"}},
    "basic-auth":     {"ann": {"auth-type": "basic", "auth-secret": "basic-secret", "auth-realm": "Restricted"}},
    # 🔴
    "snippet":        {"ann": {"configuration-snippet": 'more_set_headers "X-Foo: bar";'}},
}


def _ingress(name, host, ann, path, path_impl, extra_paths=None, tls=False, svc="echo"):
    paths = [{"path": path, "pathType": "ImplementationSpecific" if path_impl else "Prefix",
              "backend": {"service": {"name": svc, "port": {"number": 80}}}}]
    if extra_paths:
        paths += extra_paths
    obj = {"apiVersion": "networking.k8s.io/v1", "kind": "Ingress",
           "metadata": {"name": name, "namespace": "default", "annotations": ann},
           "spec": {"ingressClassName": "nginx",
                    "rules": [{"host": host, "http": {"paths": paths}}]}}
    if tls:
        obj["spec"]["tls"] = [{"hosts": [host], "secretName": f"{name}-tls"}]
    return obj


def make_ingresses(name, spec):
    """반환: Ingress 객체 리스트(canary는 base+canary 쌍)."""
    ann = {P + k: v for k, v in spec["ann"].items()}
    host = f"{name}.example.com"
    path = spec.get("path", "/")
    pi = bool(spec.get("path"))
    if spec.get("canary_pair"):
        # base(어노테이션 없음) + canary(어노테이션) 쌍. nginx provider가 결합.
        # 카나리는 base와 다른 백엔드를 가리켜야 가중치/헤더 분할이 출력에 표현됨
        # (동일 서비스면 분할이 구조적으로 드러나지 않아 변환 충실도를 측정 못 함).
        base = _ingress(f"{name}-base", host, {}, "/", False)
        canary = _ingress(name, host, ann, "/", False, svc="echo-canary")
        return [base, canary]
    extra = None
    if spec.get("paths2"):
        extra = [{"path": "/v2", "pathType": "Prefix",
                  "backend": {"service": {"name": "echo2", "port": {"number": 80}}}}]
    objs = [_ingress(name, host, ann, path, pi, extra, spec.get("tls", False))]
    if spec.get("hosts2"):
        objs.append(_ingress(f"{name}2", f"{name}2.example.com", {}, "/", False))
    return objs


def to_yaml(objs):
    try:
        import yaml
        return yaml.safe_dump_all(objs, sort_keys=False)
    except ImportError:
        return "\n---\n".join(json.dumps(o, indent=2) for o in objs)


# i2gw가 어노테이션을 거절했음을 나타내는 문구(소문자 비교). 통지 형태가 여러 가지라
# 2종("Unsupported annotation"/"Failed to apply")만으로는 일부 거절(예: 세션 어피니티의
# "failed to parse ... Session affinity is not supported", backend-tls의 ERROR strict
# validation)을 놓친다.
_DECLINE_MARKERS = (
    "unsupported annotation",
    "failed to apply",
    "failed to parse",
    "is not supported",
    "not supported",
    "failed strict validation",
)


def _ann_in_line(ann, ln):
    """어노테이션 키가 단어 경계로 등장하는지. 접두 substring 충돌 방지
    (예: canary 가 canary-by-header 안에 우연히 들어맞는 것을 배제)."""
    key = P + ann
    i = ln.find(key)
    while i != -1:
        nxt = ln[i + len(key): i + len(key) + 1]
        if nxt == "" or not (nxt.isalnum() or nxt == "-"):
            return True
        i = ln.find(key, i + 1)
    return False


def classify(spec, after, log):
    """미변환 통지를 잡는다(_DECLINE_MARKERS, 어노테이션 키 단어경계 매칭).
    한계: i2gw가 통지 없이 어노테이션을 조용히 버리는 경우(예: header-modifier의
    x-forwarded-prefix)는 로그로 탐지 불가 -> FINAL 수동 보정으로 처리.
    """
    anns = list(spec["ann"].keys())
    declined = {}  # ann -> reason
    for ln in log.splitlines():
        low = ln.lower()
        if not any(m in low for m in _DECLINE_MARKERS):
            continue
        for a in anns:
            if not _ann_in_line(a, ln):
                continue
            declined[a] = ln.rsplit(":", 1)[-1].strip() or "declined"
    info_caveat = re.search(r"┌─\s*INFO\b", log) is not None
    if not anns:
        return "native", declined, info_caveat
    if all(a in declined for a in anns):
        return "no", declined, info_caveat
    if declined:                 # 일부만 변환(나머지 거절)
        return "partial", declined, info_caveat
    if info_caveat:              # 변환되나 의미차 INFO 주의(예: regex 대소문자)
        return "partial", declined, info_caveat
    return "converts", declined, info_caveat


# 자동분류가 i2gw 통지 문구 한계로 놓친 것 수동 확정(근거=gateway/*.out.yaml + logs/*.log 검토).
FINAL = {
    "backend-tls": ("partial", "backend-protocol:HTTPS 단독은 거절(strict validation: proxy-ssl-verify/secret/server-name/name 전부 필요). 전체 제공 시 BackendTLSPolicy 변환"),
    "timeout":     ("partial", "timeouts 필드는 생성되나 값 비충실(입력 10/60/60s가 request:10m0s 고정값으로, best-effort 매핑)"),
    "header-modifier": ("no", "x-forwarded-prefix가 출력에 RequestHeaderModifier 필터 없이 조용히 누락(거절 통지도 없음). proxy-set-headers/custom-headers는 미변환. ingress-nginx 헤더 수정 어노테이션은 i2gw 등가물 없음"),
}


def run():
    results = {}
    ver = subprocess.run(["ingress2gateway", "version"], capture_output=True, text=True).stdout.strip()
    for name, spec in SAMPLES.items():
        ing_objs = make_ingresses(name, spec)
        ing_path = ING / f"{name}.yaml"
        ing_path.write_text(to_yaml(ing_objs))
        proc = subprocess.run(
            ["ingress2gateway", "print", "--input-file", str(ing_path), "--providers", "ingress-nginx"],
            capture_output=True, text=True)
        after = proc.stdout
        log = re.sub(r"\x1b\[[0-9;]*m", "", proc.stderr)  # ANSI 제거
        # 도구 실행 자체가 실패하면 분류가 무의미(통지 부재로 거짓 converts 위험) → 즉시 중단
        if proc.returncode != 0:
            sys.exit(f"[abort] ingress2gateway 실패(rc={proc.returncode}) sample={name}\n{log}")
        (GW / f"{name}.out.yaml").write_text(after)
        (LOG / f"{name}.txt").write_text(log)
        cls, declined, info = classify(spec, after, log)
        manual = ""
        if name in FINAL:
            cls, manual = FINAL[name]
        results[name] = {
            "annotations": list(spec["ann"].keys()),
            "class": cls,
            "manual_note": manual,           # 수동 확정 사유(있으면 자동분류 보정)
            "declined": declined,            # ann -> i2gw가 댄 미변환 이유
            "info_caveat": info,
            "converted_kinds": sorted(set(re.findall(r"^kind: (\w+)", after, re.M))),
            # 출력에 등장한 type: 값 전부(필터 + 경로 매치 타입 PathPrefix 등 혼재).
            # 변환 산출의 구조 지문 용도라 이름을 emitted_types로 정확히 한다.
            "emitted_types": sorted(set(re.findall(r"type: (\w+)", after))),
        }
    out = {"i2gw_version": ver, "samples": results}
    (HERE / "results.json").write_text(json.dumps(out, indent=2, ensure_ascii=False))
    # 요약 출력
    print(f"# {ver}")
    for n, r in results.items():
        dec = ",".join(r["declined"].keys()) or "-"
        print(f"{r['class']:9} {n:18} kinds={r['converted_kinds']} types={r['emitted_types']} "
              f"declined={dec} info={r['info_caveat']}")


if __name__ == "__main__":
    run()
