#!/usr/bin/env bash
# 주말 무인 측정 (2026-08-20 밤 ~ 08-24 월 아침 확인, 사용자 승인).
#
#   1부 guardrail 오버헤드: 무정책 대 guardrail-통과, 100/200rps x 5회 (약 75분)
#   2부 FailOpen + Response 페이즈 증거 (약 20분)
#   3부 A/B reuse 모드: direct 대 gateway, 연결 재사용 조건 (약 75분)
#   4부 재현성 리플레이: run_axes.sh 전체 재실행 (약 80분)
#
# 원칙: 부 단위 산출물(어디서 죽어도 재개 가능), 부 종료마다 커밋·푸시(무인
# 진행 기록), 각 부가 끝나면 격리 복원. 스냅샷 복원과 이미지 빌드 없음.
# 사용: ./run_weekend.sh <OUT_BASE>   (예: runs/weekend-0820)
set -uo pipefail

BASE="$1"; CTX="mcp-migration"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
REPO="$(cd "$STUDY/.." && pwd)"
MCPSTUDY="$(cd "$REPO/mcp-migration/studies/stateless-scaleout" && pwd)"
GWDIR="$MCPSTUDY/k8s/agentgateway"
GRDIR="$STUDY/k8s/guardrail"
LOADGEN="$MCPSTUDY/harness/loadgen.py"
PY=/tmp/mcpvenv/bin/python
COOLDOWN=180
mkdir -p "$STUDY/$BASE"
OUT="$STUDY/$BASE"
log() { echo "[$(date '+%m-%d %H:%M')] $*"; }
note() { echo "$*" >> "$OUT/FINDINGS.md"; }

push_progress() { # push_progress <메시지>
  ( cd "$REPO" && git add agentgateway-study/runs >/dev/null 2>&1 \
    && git commit -q -m "주말 무인 측정: $1" >/dev/null 2>&1 \
    && git pull --rebase -q origin main >/dev/null 2>&1 \
    && git push -q origin main >/dev/null 2>&1 ) || true
}

gw_install() {
  AGW_VER=v1.4.1 bash "$GWDIR/install.sh" >> "$OUT/install.log" 2>&1
  sleep 30
  kubectl --context $CTX apply -f "$GWDIR/gateway.yaml" >> "$OUT/install.log" 2>&1
  sleep 15
  GW=$(kubectl --context $CTX -n agentgateway-system get gateway agentgateway-proxy -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
  [ -z "$GW" ] && { log "[중단] 게이트웨이 주소 없음"; note "**중단**: 게이트웨이 주소 없음"; exit 1; }
  GW="http://$GW"
}

cell() { # cell <name> <url> <rps> <conc> <conn-mode>
  "$PY" "$LOADGEN" --url "$2" --dialect b --tool echo \
    --concurrency "$4" --duration 30 --conn-mode "$5" --rps "$3" \
    --out "$OUT/$1.json" >/dev/null 2>&1
  "$PY" -c "
import json
d=json.load(open('$OUT/$1.json'))
err=sum(d.get('errors', {}).values())
print(f\"achieved={d['achieved_rps']:.1f} p50={d['latency_ms']['p50']:.1f} p99={d['latency_ms']['p99']:.1f} err={err}\")"
}

call() { # call <tool> <args-json>
  curl -s -w '\nHTTP %{http_code}' -X POST "$GW/b" \
    -H 'Accept: application/json, text/event-stream' \
    -H 'Content-Type: application/json' \
    -H 'MCP-Protocol-Version: 2026-07-28' \
    -H 'Mcp-Method: tools/call' -H "Mcp-Name: $1" \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"'$1'","arguments":'$2',"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"weekend","version":"0.1"},"io.modelcontextprotocol/clientCapabilities":{}}}}' \
    | head -c 300 | tr '\n' ' '
  echo
}

guardrail_deploy() {
  kubectl --context $CTX -n $NS delete configmap guardrail-code >/dev/null 2>&1
  kubectl --context $CTX -n $NS create configmap guardrail-code \
    --from-file="$GRDIR/server.py" --from-file="$GRDIR/ext_mcp_pb2.py" \
    --from-file="$GRDIR/ext_mcp_pb2_grpc.py" >> "$OUT/install.log" 2>&1
  kubectl --context $CTX apply -f "$GRDIR/guardrail.yaml" >> "$OUT/install.log" 2>&1
  kubectl --context $CTX -n $NS rollout status deploy/guardrail --timeout=300s >> "$OUT/install.log" 2>&1
}

guardrail_policy() { # guardrail_policy <failureMode> <phase>
  cat <<YAML | kubectl --context $CTX apply -f - >> "$OUT/install.log" 2>&1
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata:
  name: wk-guardrail
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
              tools/call: $2
            remote:
              backendRef:
                kind: Service
                name: guardrail
                namespace: mcp-pilot
                port: 50051
              failureMode: $1
YAML
  sleep 12
}
guardrail_teardown() {
  kubectl --context $CTX -n $NS delete agentgatewaypolicy wk-guardrail >/dev/null 2>&1
  kubectl --context $CTX delete -f "$GRDIR/guardrail.yaml" >/dev/null 2>&1
  kubectl --context $CTX -n $NS delete configmap guardrail-code >/dev/null 2>&1
}

echo "# 주말 무인 측정 (자동 생성)" > "$OUT/FINDINGS.md"
note ""
note "시작 $(date '+%Y-%m-%d %H:%M'). 1부 guardrail 오버헤드, 2부 FailOpen/Response,"
note "3부 A/B reuse 모드, 4부 run_axes 리플레이."
note ""

# ═══ 1부: guardrail 오버헤드 ═══════════════════════════════════════════
log "=== 1부: guardrail 오버헤드 ==="
gw_install
kubectl --context $CTX -n $NS scale deploy/mcp-a --replicas=1 >/dev/null 2>&1
kubectl --context $CTX -n $NS scale deploy/mcp-b --replicas=1 >/dev/null 2>&1
guardrail_deploy
note "## 1부. guardrail 오버헤드 (echo, close 모드, 쿨다운 ${COOLDOWN}초)"
note ""
note "자원 통제: guardrail 파드와 게이트웨이를 설치한 채로 두 조건을 모두 쟀다."
note "차이는 guardrail 정책(tools/call: Request, FailClosed)의 유무뿐이다."
note ""
for arm in off on; do
  if [ "$arm" = on ]; then guardrail_policy FailClosed Request; fi
  for rps in 100 200; do
    conc=8; [ "$rps" = 200 ] && conc=16
    note "- guardrail=$arm ${rps}rps:"
    for n in 1 2 3 4 5; do
      R=$(cell "g4x-${arm}-rps${rps}-n${n}" "$GW/b" "$rps" "$conc" close)
      note "  - n$n: $R"
      sleep $COOLDOWN
    done
  done
done
note ""
push_progress "1부 guardrail 오버헤드 완료"

# ═══ 2부: FailOpen + Response 페이즈 ══════════════════════════════════
log "=== 2부: FailOpen + Response 페이즈 ==="
note "## 2부. FailOpen과 Response 페이즈"
note ""
kubectl --context $CTX -n $NS delete agentgatewaypolicy wk-guardrail >/dev/null 2>&1
sleep 8
guardrail_policy FailOpen Request
kubectl --context $CTX -n $NS scale deploy/guardrail --replicas=0 >/dev/null 2>&1
sleep 20
note "### FailOpen, guardrail 서버 부재"
note "- get-sum a=2 (FailOpen이면 통과 기대): \`$(call get-sum '{"a":2,"b":2}')\`"
note "- echo: \`$(call echo '{"message":"ping"}')\`"
note ""
kubectl --context $CTX -n $NS scale deploy/guardrail --replicas=1 >/dev/null 2>&1
kubectl --context $CTX -n $NS rollout status deploy/guardrail --timeout=300s >> "$OUT/install.log" 2>&1
kubectl --context $CTX -n $NS delete agentgatewaypolicy wk-guardrail >/dev/null 2>&1
sleep 8
guardrail_policy FailClosed Full
note "### Response 페이즈 (methods: tools/call = Full)"
note "- echo 호출: \`$(call echo '{"message":"ping"}')\`"
sleep 5
note "- guardrail 로그 끝부분 (RESP 줄 = 응답 페이즈 수신 증거):"
note '```'
kubectl --context $CTX -n $NS logs deploy/guardrail --tail=6 >> "$OUT/FINDINGS.md" 2>/dev/null
note '```'
note ""
guardrail_teardown
push_progress "2부 FailOpen/Response 완료"

# ═══ 3부: A/B reuse 모드 ═════════════════════════════════════════════
log "=== 3부: A/B reuse 모드 ==="
note "## 3부. 게이트웨이 유무 A/B, 연결 재사용(reuse) 모드"
note ""
note "구성은 결과 6과 동일(게이트웨이 상주, 대상 주소만 변경). 연결 방식만"
note "close에서 reuse로 바꿨다. direct -> gw 교대, 쿨다운 ${COOLDOWN}초."
note ""
DIRECT_URL="http://192.168.2.231/mcp"
for rps in 100 200; do
  conc=8; [ "$rps" = 200 ] && conc=16
  for n in 1 2 3 4 5; do
    R=$(cell "abr-direct-rps${rps}-n${n}" "$DIRECT_URL" "$rps" "$conc" reuse)
    note "- direct n$n (${rps}rps): $R"
    sleep $COOLDOWN
    R=$(cell "abr-gw-rps${rps}-n${n}" "$GW/b" "$rps" "$conc" reuse)
    note "- gw     n$n (${rps}rps): $R"
    sleep $COOLDOWN
  done
done
note ""
log "3부 종료, 게이트웨이 제거"
bash "$GWDIR/uninstall.sh" >> "$OUT/install.log" 2>&1
push_progress "3부 A/B reuse 완료"

# ═══ 4부: run_axes 리플레이 ══════════════════════════════════════════
log "=== 4부: run_axes.sh 리플레이 ==="
note "## 4부. 재현성 리플레이"
note ""
"$DIR/run_axes.sh" "$PY" "$STUDY/runs/replay-0820" > "$STUDY/runs/replay-0820-run.log" 2>&1
note "run_axes.sh 전체 재실행 완료. 결과 = \`runs/replay-0820/FINDINGS.md\`."
note "발행 수치와의 대조는 월요일 판독에서 한다."
note ""
note "---"
note "주말 무인 측정 종료 $(date '+%Y-%m-%d %H:%M'). 격리 상태로 복원됨."
push_progress "4부 리플레이 완료 (주말 측정 전체 종료)"
log "=== 주말 무인 측정 완료 ==="
