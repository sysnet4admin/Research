#!/usr/bin/env python3
"""실제 도구와 실제 클라이언트 보강 측정(2026-09-28) 중 측정 1의 셀 프로브. 실제 쿠버네티스 MCP 서버(kmcp)에
두 게이트웨이를 거쳐 같은 배터리를 보내고 판정을 JSON 으로 남긴다.

배터리: 목록, dev 삭제, prod 삭제, 허용된 다른 도구(pods_list_in_namespace),
규칙에 없는 도구(pods_get). 삭제 대상은 회차마다 새로 만드는 더미 파드이고
실제로 지워졌는지는 게이트웨이 응답과 따로 kubectl 로 확인한다.

사용: kmcp_probe.py --gw agw|ar --cell <이름> --round <n> --out <디렉터리>
"""
import argparse, json, os, subprocess, time
from pathlib import Path
import httpx

# 게이트웨이 주소는 환경변수로 받는다(cfp_0928.sh 가 클러스터의 Service 에서 읽어 넘긴다).
GW = {"agw": (os.environ.get("AGW_URL", "") + "/k", ""), "ar": (os.environ.get("AR_URL", "") + "/kmcp", "kmcp__")}
CTX = os.environ.get("KCTX", "aaif-benchmark")


def kubectl(*a):
    return subprocess.run(["kubectl", "--context", CTX, *a], capture_output=True, text=True)


def sse_json(text):
    for line in text.splitlines():
        if line.startswith("data: "):
            try:
                return json.loads(line[6:])
            except json.JSONDecodeError:
                return None
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return None


class Session:
    def __init__(self, url):
        self.url, self.c, self.sid, self.rid = url, httpx.Client(timeout=20), None, 0

    def post(self, method, params=None, notify=False):
        self.rid += 1
        h = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
        if self.sid:
            h["Mcp-Session-Id"] = self.sid
        body = {"jsonrpc": "2.0", "method": method}
        if not notify:
            body["id"] = self.rid
        if params is not None:
            body["params"] = params
        r = self.c.post(self.url, headers=h, content=json.dumps(body))
        return r

    def initialize(self):
        r = self.post("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                     "clientInfo": {"name": "kmcp-probe", "version": "1"}})
        self.sid = r.headers.get("mcp-session-id")
        self.post("notifications/initialized", notify=True)
        return r


def verdict(r):
    """HTTP 응답 -> (분류, 요약). ok / tool-error / jsonrpc-error / http-NNN."""
    j = sse_json(r.text)
    if r.status_code != 200:
        return f"http-{r.status_code}", r.text[:160]
    if j is None:
        return "unparsed", r.text[:160]
    if "error" in j:
        return "jsonrpc-error", json.dumps(j["error"])[:160]
    res = j.get("result", {})
    if res.get("isError"):
        return "tool-error", json.dumps(res.get("content"))[:160]
    return "ok", json.dumps(res.get("content"))[:160]


def pod_exists(ns, name):
    """살아 있는(삭제 요청을 받지 않은) 파드면 True. 없거나 종료 중이면 False."""
    r = kubectl("-n", ns, "get", "pod", name, "-o", "jsonpath={.metadata.deletionTimestamp}")
    return r.returncode == 0 and r.stdout.strip() == ""


def make_pod(ns, name):
    kubectl("-n", ns, "run", name, "--image=registry.k8s.io/pause:3.10", "--restart=Never",
            "--labels=kmcp-probe=1")
    kubectl("-n", ns, "wait", "--for=condition=Ready", f"pod/{name}", "--timeout=90s")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gw", required=True, choices=GW)
    ap.add_argument("--cell", required=True)
    ap.add_argument("--round", type=int, required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    url, prefix = GW[a.gw]
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)

    tag = f"{a.gw}-{a.cell}-r{a.round}".lower().replace("_", "-")
    dev_pod, prod_pod = f"dummy-{tag}"[:60], f"dummy-{tag}"[:60]  # 네임스페이스가 달라 같은 이름을 쓴다
    make_pod("dev", dev_pod)
    make_pod("prod", prod_pod)

    s = Session(url)
    rec = {"gw": a.gw, "cell": a.cell, "round": a.round, "ts": time.time(), "probes": {}}
    init = s.initialize()
    rec["initialize"] = init.status_code

    r = s.post("tools/list", {})
    j = sse_json(r.text) or {}
    names = [t["name"] for t in j.get("result", {}).get("tools", [])] if r.status_code == 200 else []
    rec["probes"]["list"] = {"code": r.status_code, "count": len(names),
                             "has_delete": f"{prefix}pods_delete" in names,
                             "has_list_ns": f"{prefix}pods_list_in_namespace" in names,
                             "has_get": f"{prefix}pods_get" in names,
                             "raw": r.text[:200] if r.status_code != 200 else ""}

    def call(key, tool, args, ns=None, pod=None):
        before = pod_exists(ns, pod) if ns else None
        r = s.post("tools/call", {"name": f"{prefix}{tool}", "arguments": args})
        v, summary = verdict(r)
        entry = {"code": r.status_code, "verdict": v, "summary": summary}
        if ns:
            time.sleep(2)
            entry["pod_before"] = before
            entry["pod_after"] = pod_exists(ns, pod)
            entry["deleted"] = bool(before and not entry["pod_after"])
        rec["probes"][key] = entry

    call("delete_dev", "pods_delete", {"name": dev_pod, "namespace": "dev"}, "dev", dev_pod)
    call("delete_prod", "pods_delete", {"name": prod_pod, "namespace": "prod"}, "prod", prod_pod)
    call("list_ns_dev", "pods_list_in_namespace", {"namespace": "dev"})
    call("get_prod", "pods_get", {"name": prod_pod, "namespace": "prod"})

    # 남은 더미 정리(다음 회차와 섞이지 않게)
    kubectl("-n", "dev", "delete", "pod", dev_pod, "--ignore-not-found", "--wait=false")
    kubectl("-n", "prod", "delete", "pod", prod_pod, "--ignore-not-found", "--wait=false")

    (out / f"{tag}.json").write_text(json.dumps(rec, ensure_ascii=False, indent=1))
    p = rec["probes"]
    print(f"{a.gw} {a.cell} r{a.round}: list={p['list']['count']}"
          f"(del={p['list']['has_delete']},lsns={p['list']['has_list_ns']},get={p['list']['has_get']}) "
          f"dev={p['delete_dev']['verdict']}/deleted={p['delete_dev']['deleted']} "
          f"prod={p['delete_prod']['verdict']}/deleted={p['delete_prod']['deleted']} "
          f"list_ns={p['list_ns_dev']['verdict']} get={p['get_prod']['verdict']}")


if __name__ == "__main__":
    main()
