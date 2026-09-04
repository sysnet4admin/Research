#!/usr/bin/env bash
# [rv 사본] v1.5.0 + aaif-benchmark 재측정용. 원본과의 차이 = CTX, 설치 사본, AGW_VER.
# guardrail 전체 재측정: off/on 교대 설계 (2026-08-26 등록, 18시 무인 기동).
#
# 목적: 주말 1부와 grr-0826이 off 팔 전체 -> on 팔 전체의 순차 측정이라
# 시간 드리프트가 증분에 섞였을 가능성을 가른다. 여기서는 off/on을 회차
# 안에서 인접 교대(ABBA: 홀수 회차 off->on, 짝수 회차 on->off)로 잰다.
# 교대 후에도 close +1ms가 남으면 폭주 경합 실체, 사라지면 드리프트였다.
# close 400rps를 추가해 큐잉설(부하 비례)도 함께 흔든다.
#
# 셀: close x {100,200,400} + reuse x {100,200}, 각 rps에 off/on 쌍 x 5회
#     = 25쌍 = 50셀. 쿨다운 180초. 예상 약 3시간 15분.
# 사용: ./gr_matrix.sh <OUT_BASE>   (예: runs/grm-0826)
set -uo pipefail

BASE="$1"; CTX="aaif-benchmark"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
REPO="$(cd "$STUDY/.." && pwd)"
MCPSTUDY="$(cd "$REPO/mcp-migration/studies/stateless-scaleout" && pwd)"
GWDIR="$MCPSTUDY/k8s/agentgateway"
GRDIR="$STUDY/k8s/guardrail"
LOADGEN="$MCPSTUDY/harness/loadgen.py"
PY="$HOME/.venvs/mcpbench/bin/python"
COOLDOWN="${RV_COOLDOWN:-180}"
mkdir -p "$STUDY/$BASE"; OUT="$STUDY/$BASE"
log() { echo "[$(date '+%m-%d %H:%M')] $*"; }
note() { echo "$*" >> "$OUT/FINDINGS.md"; }
# push_progress: 내부 진행 기록용(무인 실행 중 원격 백업). 클론해서 재현할
# 때는 이 함수 본문을 비우고 실행할 것. 그대로 두면 자기 저장소 main에
# 커밋과 푸시를 시도한다.
push_progress() {
  ( cd "$REPO" && git add agentgateway-study/runs >/dev/null 2>&1 \
    && git commit -q -m "guardrail 교대 재측정: $1" >/dev/null 2>&1 \
    && git pull --rebase --autostash -q origin main >/dev/null 2>&1 \
    && git push -q origin main >/dev/null 2>&1 ) || true
}

"$PY" -c "import httpx" 2>/dev/null || {
  echo "[중단] $PY 에 httpx 없음(loadgen 의존성). venv 재구성:"
  echo "  /opt/homebrew/bin/python3.13 -m venv $HOME/.venvs/mcpbench && $HOME/.venvs/mcpbench/bin/pip install httpx"
  exit 1
}

echo "# guardrail 전체 재측정, off/on 교대 (자동 생성)" > "$OUT/FINDINGS.md"
note ""
note "시작 $(date '+%Y-%m-%d %H:%M'). ABBA 교대(홀수 회차 off->on, 짝수 on->off),"
note "정책 토글 후 웜업 5호출, close x {100,200,400} + reuse x {100,200}, 5회."
note "- 전원 상태: $(pmset -g batt | head -1 | sed 's/Now drawing from //')"
note ""

log "게이트웨이 설치"
AGW_VER=v1.5.0 bash "$DIR/install_agw.sh" >> "$OUT/install.log" 2>&1
sleep 30
kubectl --context $CTX apply -f "$GWDIR/gateway.yaml" >> "$OUT/install.log" 2>&1
sleep 15
GW=$(kubectl --context $CTX -n agentgateway-system get gateway agentgateway-proxy -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
[ -z "$GW" ] && { note "**중단**: 게이트웨이 주소 없음"; push_progress "중단"; exit 1; }
GW="http://$GW"
kubectl --context $CTX -n $NS scale deploy/mcp-a --replicas=1 >/dev/null 2>&1
kubectl --context $CTX -n $NS scale deploy/mcp-b --replicas=1 >/dev/null 2>&1

log "guardrail 배포"
kubectl --context $CTX -n $NS delete configmap guardrail-code >/dev/null 2>&1
kubectl --context $CTX -n $NS create configmap guardrail-code \
  --from-file="$GRDIR/server.py" --from-file="$GRDIR/ext_mcp_pb2.py" \
  --from-file="$GRDIR/ext_mcp_pb2_grpc.py" >> "$OUT/install.log" 2>&1
kubectl --context $CTX apply -f "$GRDIR/guardrail.yaml" >> "$OUT/install.log" 2>&1
kubectl --context $CTX -n $NS rollout status deploy/guardrail --timeout=300s >> "$OUT/install.log" 2>&1
for i in $(seq 1 30); do
  EP=$(kubectl --context $CTX -n $NS get endpoints guardrail -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null)
  [ -n "$EP" ] && break; sleep 2
done
note "- guardrail 엔드포인트: ${EP:-없음}"
note ""

warmup() { # 정책 토글 직후 첫 셀 오염 방지 (주말 on-100 n1의 p99 99.4 이상치 교훈)
  for i in 1 2 3 4 5; do
    curl -s -o /dev/null --max-time 5 -X POST "$GW/b" \
      -H 'Accept: application/json, text/event-stream' -H 'Content-Type: application/json' \
      -H 'MCP-Protocol-Version: 2026-07-28' -H 'Mcp-Method: tools/call' -H 'Mcp-Name: echo' \
      -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo","arguments":{"message":"w"},"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"grm","version":"0.1"},"io.modelcontextprotocol/clientCapabilities":{}}}}'
  done
}

policy_on() {
  cat <<YAML | kubectl --context $CTX apply -f - >> "$OUT/install.log" 2>&1
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata:
  name: grm-guardrail
  namespace: mcp-pilot
spec:
  targetRefs:
    - group: agentgateway.dev
      kind: AgentgatewayBackend
      name: mcp-b-stateless
  backend:
    mcp:
      guardrails:
        processors:
          - methods:
              tools/call: Request
            remote:
              backendRef:
                kind: Service
                name: guardrail
                namespace: mcp-pilot
                port: 50051
              failureMode: FailClosed
YAML
  sleep 12; warmup
}
policy_off() {
  kubectl --context $CTX -n $NS delete agentgatewaypolicy grm-guardrail >/dev/null 2>&1
  sleep 8; warmup
}

cell() { # cell <arm> <mode> <rps> <conc> <n>
  local arm="$1" mode="$2" rps="$3" conc="$4" n="$5"
  local f="$OUT/grm-${arm}-${mode}-rps${rps}-n${n}.json"
  "$PY" "$LOADGEN" --url "$GW/b" --dialect b --tool echo \
    --concurrency "$conc" --duration "${RV_DURATION:-30}" --conn-mode "$mode" --rps "$rps" \
    --out "$f" >> "$OUT/loadgen.log" 2>&1
  if [ ! -s "$f" ]; then
    note "  - $arm $mode ${rps}rps n$n: **실패, JSON 미생성. 중단**"
    push_progress "중단(셀 산출물 미생성)"
    exit 1
  fi
  R=$("$PY" -c "
import json
d=json.load(open('$f'))
err=d.get('gateway_error',0)+d.get('other_fail',0)+d.get('session_loss',0)
print(f\"achieved={d['achieved_rps']:.1f} p50={d['latency_ms']['p50']:.1f} p99={d['latency_ms']['p99']:.1f} err={err}\")")
  note "  - $arm $mode ${rps}rps n$n: $R"
  sleep $COOLDOWN
}

note "## 셀 기록 (교대 순서 그대로)"
note ""
CURRENT=off   # 시작 상태: 정책 없음
for spec in close:100:8 close:200:16 close:400:32 reuse:100:8 reuse:200:16; do
  mode="${spec%%:*}"; rest="${spec#*:}"; rps="${rest%%:*}"; conc="${rest#*:}"
  log "=== $mode ${rps}rps (5쌍 교대) ==="
  for n in $(seq 1 "${RV_ROUNDS:-5}"); do
    if [ $((n % 2)) -eq 1 ]; then order="off on"; else order="on off"; fi
    for arm in $order; do
      if [ "$arm" != "$CURRENT" ]; then
        if [ "$arm" = on ]; then policy_on; else policy_off; fi
        CURRENT="$arm"
      fi
      cell "$arm" "$mode" "$rps" "$conc" "$n"
    done
  done
  push_progress "$mode ${rps}rps 완료"
done

log "정리"
kubectl --context $CTX -n $NS delete agentgatewaypolicy grm-guardrail >/dev/null 2>&1
kubectl --context $CTX delete -f "$GRDIR/guardrail.yaml" >/dev/null 2>&1
kubectl --context $CTX -n $NS delete configmap guardrail-code >/dev/null 2>&1
echo "[rv] 게이트웨이 유지 (체인 다음 단계가 이어받음)" >> "$OUT/install.log"
note ""
note "---"
note "종료 $(date '+%Y-%m-%d %H:%M'). 격리 복원됨. 판독은 rps별 off/on 쌍의"
note "p50 차이(교대라 드리프트 상쇄)와 400rps의 증분 크기(큐잉설 판별)."
push_progress "교대 재측정 전체 종료"
log "=== gr_matrix 완료 ==="
