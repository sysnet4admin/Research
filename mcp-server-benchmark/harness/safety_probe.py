#!/usr/bin/env python3
"""안전 어포던스 실측 (재시도판).
실패 원인 2건 해소: ① 셸의 NODE_OPTIONS가 깨진 preload를 걸어 node가 죽음 → env에서 제거
                    ② 응답이 길어 줄 단위 파싱이 잘림 → 스트림 전체를 모아 파싱
각 서버를 기본/read-only로 띄워 tools/list 개수와 도구 이름을 센다. LLM 미사용."""
import json, os, subprocess, shlex, time
from pathlib import Path

OUT = Path(os.environ.get("MCP_BENCH_OUT", Path(__file__).resolve().parents[1]/"studies"/"server-comparison"))
KCFG = os.environ.get("KUBECONFIG", str(Path.home()/".kube/aiops-only.kubeconfig"))
HOME = str(Path.home())

SERVERS = [
    ("containers", "어노테이션 필터",
     f"npx -y kubernetes-mcp-server@0.0.66 --kubeconfig {KCFG}",
     f"npx -y kubernetes-mcp-server@0.0.66 --kubeconfig {KCFG} --read-only"),
    ("flux159", "하드코딩 목록",
     "npx -y mcp-server-kubernetes", "npx -y mcp-server-kubernetes"),  # ro는 env로
    ("azure-k8s", "access-level",
     f"{HOME}/.local/bin/mcp-kubernetes --access-level readwrite",
     f"{HOME}/.local/bin/mcp-kubernetes --access-level readonly"),
    ("rohitg00", "호출 시점만 차단",
     "uvx --from kubectl-mcp-server kubectl-mcp-serve serve --transport stdio",
     "uvx --from kubectl-mcp-server kubectl-mcp-serve serve --transport stdio --read-only"),
    ("ro-only", "구조적(쓰기 경로 없음)",
     "npx -y @patrickdappollonio/mcp-kubernetes-ro",
     "npx -y @patrickdappollonio/mcp-kubernetes-ro"),
    ("reza", "등록 시점 차단",
     f"{HOME}/.local/bin/k8s-mcp-server -mode stdio",
     f"{HOME}/.local/bin/k8s-mcp-server -mode stdio -read-only"),
]

REQ = ('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18",'
       '"capabilities":{},"clientInfo":{"name":"probe","version":"1"}}}\n'
       '{"jsonrpc":"2.0","method":"notifications/initialized"}\n'
       '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}\n')

def probe(cmd, extra_env=None, timeout=180):
    env = {k: v for k, v in os.environ.items() if k != "NODE_OPTIONS"}
    env["KUBECONFIG"] = KCFG
    if extra_env:
        env.update(extra_env)
    try:
        p = subprocess.run(shlex.split(cmd), input=REQ, env=env,
                           capture_output=True, text=True, timeout=timeout)
        out = p.stdout
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or "") if isinstance(e.stdout, str) else ((e.stdout or b"").decode(errors="ignore"))
    except Exception as e:
        return None, f"실행 실패: {str(e)[:80]}"
    # 스트림 전체에서 id=2 응답을 찾는다 (한 줄이 아닐 수 있음)
    dec = json.JSONDecoder()
    i = 0
    while i < len(out):
        j = out.find("{", i)
        if j < 0: break
        try:
            obj, end = dec.raw_decode(out[j:])
        except Exception:
            i = j + 1; continue
        i = j + end
        if isinstance(obj, dict) and obj.get("id") == 2 and "result" in obj:
            tools = obj["result"].get("tools", [])
            return [t.get("name", "?") for t in tools], None
    return None, "id=2 응답 없음"

def main():
    rows = []
    for name, design, base_cmd, ro_cmd in SERVERS:
        ro_env = {"ALLOW_ONLY_READONLY_TOOLS": "true"} if name == "flux159" else None
        b, be = probe(base_cmd)
        time.sleep(2)
        r, re_ = probe(ro_cmd, ro_env)
        rows.append({"server": name, "design": design,
                     "base": len(b) if b else None, "base_err": be,
                     "ro": len(r) if r else None, "ro_err": re_,
                     "base_tools": b or [], "ro_tools": r or [],
                     "removed": sorted(set(b or []) - set(r or [])) if b and r else []})
        print(f"{name:12s} base={len(b) if b else be}  ro={len(r) if r else re_}")

    (OUT/"SAFETY_PROBE.json").write_text(json.dumps(rows, ensure_ascii=False, indent=1))
    L = ["# 안전 어포던스 실측 (tools/list 실측, 재시도판)\n",
         f"측정 시각: {time.strftime('%F %T')}. LLM 미사용, MCP 서버에 직접 JSON-RPC.\n",
         "read-only에서 목록이 줄지 않으면 '호출 시점만 차단' 설계이고, 도구 정의가",
         "그대로 컨텍스트에 실리므로 토큰 비용이 전혀 줄지 않는다.\n",
         "| 서버 | 안전 설계 | 기본 | read-only | 감소 | 감소율 |",
         "|---|---|---|---|---|---|"]
    for r in rows:
        b, ro = r["base"], r["ro"]
        if b is None or ro is None:
            L.append(f"| {r['server']} | {r['design']} | {b or '실패'} | {ro or '실패'} | - | - |")
        else:
            d = b - ro
            L.append(f"| {r['server']} | {r['design']} | {b} | {ro} | {d} | {d/b*100:.0f}% |")
    L.append("\n## read-only에서 사라진 도구\n")
    for r in rows:
        if r["removed"]:
            L.append(f"- **{r['server']}** ({len(r['removed'])}개): {', '.join(r['removed'][:12])}"
                     + (" ..." if len(r["removed"]) > 12 else ""))
        elif r["base"] and r["ro"] and r["base"] == r["ro"]:
            L.append(f"- **{r['server']}**: 변화 없음 (목록이 그대로 노출됨)")
    (OUT/"SAFETY_PROBE.md").write_text("\n".join(L) + "\n")
    print("기록 완료:", OUT/"SAFETY_PROBE.md")

if __name__ == "__main__":
    main()
