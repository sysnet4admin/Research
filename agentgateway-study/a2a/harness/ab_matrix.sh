#!/usr/bin/env bash
# 축 C: 비용 세 경로 교대 캠페인. DESIGN.md 참조.
#
# 경로: direct(LB 직접) / gwplain(게이트웨이, appProtocol 없음) /
#     gwa2a(게이트웨이, appProtocol 있음). 세 경로 모두 설치 상태 동일, 차이는
#     대상 주소뿐. 회차 안 세 경로 인접 교대 + 회차마다 순서 로테이션
#     (grm-0826 교훈: 1ms 아래 비교는 순차 경로 금지).
# 셀: {close,reuse} x {100,200rps} x 5회차 x 세 경로 = 60셀, 30초, 쿨다운 180초.
#     예상 약 3.6시간.
# 종료 시 에이전트와 게이트웨이 전부 제거(격리 복원).
# 사용: caffeinate -i nohup ./ab_matrix.sh runs/abm-0827 > /tmp/abm.log 2>&1 &
#       회차 범위 지정(보강 측정): ./ab_matrix.sh runs/abm-ext 6 20
set -uo pipefail

BASE="$1"; N_FROM="${2:-1}"; N_TO="${3:-5}"; CTX="mcp-migration"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
REPO="$(cd "$STUDY/.." && pwd)"
GWDIR="$REPO/mcp-migration/studies/stateless-scaleout/k8s/agentgateway"
LOADGEN="$DIR/loadgen_a2a.py"
PY=/tmp/mcpvenv/bin/python
COOLDOWN=180
mkdir -p "$STUDY/$BASE"; OUT="$STUDY/$BASE"
log() { echo "[$(date '+%m-%d %H:%M')] $*"; }
note() { echo "$*" >> "$OUT/FINDINGS.md"; }
# push_progress: 내부 진행 기록용(무인 실행 중 원격 백업). 클론해서 재현할
# 때는 이 함수 본문을 비우고 실행할 것.
push_progress() {
  ( cd "$REPO" && git add a2a-study/runs >/dev/null 2>&1 \
    && git commit -q -m "a2a 비용 세 경로 교대: $1" >/dev/null 2>&1 \
    && git pull --rebase --autostash -q origin main >/dev/null 2>&1 \
    && git push -q origin main >/dev/null 2>&1 ) || true
}

"$PY" -c "import httpx" 2>/dev/null || {
  echo "[중단] $PY 에 httpx 없음. venv 재구성:"
  echo "  /opt/homebrew/bin/python3.13 -m venv /tmp/mcpvenv && /tmp/mcpvenv/bin/pip install httpx"
  exit 1
}

echo "# a2a 비용 세 경로 교대 캠페인 (자동 생성)" > "$OUT/FINDINGS.md"
note ""
note "시작 $(date '+%Y-%m-%d %H:%M'). 세 경로 인접 교대 + 회차 순서 로테이션,"
note "{close,reuse} x {100,200rps} x 회차 ${N_FROM}~${N_TO}, 셀 30초, 쿨다운 ${COOLDOWN}초."
note "- 전원 상태: $(pmset -g batt | head -1 | sed 's/Now drawing from //')"
note ""

# 게이트웨이와 에이전트가 없으면 설치 (probes.sh를 먼저 돌렸으면 재사용)
GW=$(kubectl --context $CTX -n agentgateway-system get gateway agentgateway-proxy -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
if [ -z "$GW" ]; then
  log "게이트웨이 설치"
  AGW_VER=v1.4.1 bash "$GWDIR/install.sh" >> "$OUT/install.log" 2>&1
  sleep 30
  kubectl --context $CTX apply -f "$GWDIR/gateway.yaml" >> "$OUT/install.log" 2>&1
  sleep 15
  GW=$(kubectl --context $CTX -n agentgateway-system get gateway agentgateway-proxy -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
fi
[ -z "$GW" ] && { note "**중단**: 게이트웨이 주소 없음"; push_progress "중단"; exit 1; }
if ! kubectl --context $CTX -n $NS get deploy a2a-echo >/dev/null 2>&1; then
  log "에이전트 배포"
  kubectl --context $CTX -n $NS create configmap a2a-echo-code \
    --from-file="$STUDY/k8s/server.py" >> "$OUT/install.log" 2>&1
  kubectl --context $CTX apply -f "$STUDY/k8s/agent.yaml" >> "$OUT/install.log" 2>&1
  kubectl --context $CTX -n $NS rollout status deploy/a2a-echo --timeout=300s >> "$OUT/install.log" 2>&1
fi
LB=$(kubectl --context $CTX -n $NS get svc a2a-echo-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
[ -z "$LB" ] && { note "**중단**: LB 주소 없음"; push_progress "중단"; exit 1; }

url_for() {
  case "$1" in
    direct)  echo "http://$LB:9999/" ;;
    gwplain) echo "http://$GW/agent-plain" ;;
    gwa2a)   echo "http://$GW/agent" ;;
  esac
}
note "- direct=http://$LB:9999/ gwplain=http://$GW/agent-plain gwa2a=http://$GW/agent"
note ""

warmup() {
  for i in 1 2 3 4 5; do
    curl -s -o /dev/null --max-time 5 -X POST "$1" -H 'Content-Type: application/json' \
      -d '{"jsonrpc":"2.0","id":1,"method":"message/send","params":{"message":{"kind":"message","role":"user","messageId":"w","parts":[{"kind":"text","text":"w"}]}}}'
  done
}

cell() { # cell <arm> <mode> <rps> <conc> <n>
  local arm="$1" mode="$2" rps="$3" conc="$4" n="$5"
  local f="$OUT/abm-${arm}-${mode}-rps${rps}-n${n}.json"
  "$PY" "$LOADGEN" --url "$(url_for "$arm")" \
    --concurrency "$conc" --duration 30 --conn-mode "$mode" --rps "$rps" \
    --out "$f" >> "$OUT/loadgen.log" 2>&1
  if [ ! -s "$f" ]; then
    note "  - $arm $mode ${rps}rps n$n: **실패, JSON 미생성. 중단**"
    push_progress "중단(셀 산출물 미생성)"
    exit 1
  fi
  R=$("$PY" -c "
import json
d=json.load(open('$f'))
err=d.get('gateway_error',0)+d.get('other_fail',0)
print(f\"achieved={d['achieved_rps']:.1f} p50={d['latency_ms']['p50']:.1f} p99={d['latency_ms']['p99']:.1f} err={err} shed={d.get('shed')}\")")
  note "  - $arm $mode ${rps}rps n$n: $R"
  sleep $COOLDOWN
}

note "## 셀 기록 (교대 순서 그대로)"
note ""
for spec in close:100:8 close:200:16 reuse:100:8 reuse:200:16; do
  mode="${spec%%:*}"; rest="${spec#*:}"; rps="${rest%%:*}"; conc="${rest#*:}"
  log "=== $mode ${rps}rps (회차 ${N_FROM}~${N_TO} x 세 경로 로테이션) ==="
  for n in $(seq "$N_FROM" "$N_TO"); do
    case $((n % 3)) in
      1) order="direct gwplain gwa2a" ;;
      2) order="gwplain gwa2a direct" ;;
      0) order="gwa2a direct gwplain" ;;
    esac
    for arm in $order; do
      warmup "$(url_for "$arm")"
      cell "$arm" "$mode" "$rps" "$conc" "$n"
    done
  done
  push_progress "$mode ${rps}rps 완료"
done

log "정리 (격리 복원)"
kubectl --context $CTX delete -f "$STUDY/k8s/agent.yaml" >/dev/null 2>&1
kubectl --context $CTX -n $NS delete configmap a2a-echo-code >/dev/null 2>&1
bash "$GWDIR/uninstall.sh" >> "$OUT/install.log" 2>&1
note ""
note "---"
note "종료 $(date '+%Y-%m-%d %H:%M'). 격리 복원됨. 판독은 회차 안 인접 쌍의"
note "p50 차이(gwplain-direct = 프록시 비용, gwa2a-gwplain = A2A 처리 비용)와"
note "달성 rps(생성기 포화 확인)."
push_progress "세 경로 교대 전체 종료"
log "=== ab_matrix 완료 ==="
