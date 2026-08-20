#!/usr/bin/env bash
# A/B 추가 측정: 게이트웨이 유무 비교 (2026-08-19, ONE Summit CFP 보강).
#
# arm-direct: loadgen -> mcp-b Service(LB) 직접   http://192.168.2.231/mcp
# arm-gw:     loadgen -> agentgateway v1.4.1 -> mcp-b (정책 0개)
#
# 핵심 설계: **게이트웨이를 띄워 둔 채로 arm-direct를 잰다.** 두 arm에서
# 클러스터 자원 점유 상태를 동일하게 두고 경로만 바꿔 절대 비교를 성립시킨다.
# (mcp-migration 본측정의 게이트웨이 셀이 직접 경로와 절대 비교 불가였던
# 이유가 자원 조건 차이였다.)
#
# 부하: P4와 동일. 100/200rps x 5회 x 30초 close 모드, 셀 간 쿨다운 180초
# (conntrack TIME_WAIT 누적 방지, mcp-migration 1차 무효 사고의 교훈).
# 회차 안에서 direct -> gw 순으로 번갈아 실행해 시간 흐름 편향을 양쪽에
# 고르게 분산한다.
#
# 사용: ./run_ab.sh <PYTHON> <OUT_DIR>
set -uo pipefail

PY="$1"; OUT="$2"
CTX="mcp-migration"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCPSTUDY="$(cd "$DIR/../../mcp-migration/studies/stateless-scaleout" && pwd)"
GWDIR="$MCPSTUDY/k8s/agentgateway"
LOADGEN="$MCPSTUDY/harness/loadgen.py"
COOLDOWN=180
mkdir -p "$OUT"

log() { echo "[$(date '+%m-%d %H:%M')] $*"; }
note() { echo "$*" >> "$OUT/FINDINGS.md"; }

echo "# A/B 측정: 게이트웨이 유무 (자동 생성)" > "$OUT/FINDINGS.md"
note ""
note "실행 $(date '+%Y-%m-%d %H:%M'). arm-direct = mcp-b LB 직접, arm-gw = agentgateway 경유."
note "자원 통제: **게이트웨이(컨트롤 플레인 + 프록시)를 설치한 채로 두 arm을 모두 쟀다.**"
note "arm 간 차이는 부하 생성기의 대상 주소뿐이다. 부하는 100/200rps x 5회 x 30초"
note "close 모드, 셀 간 쿨다운 ${COOLDOWN}초, 회차 안에서 direct -> gw 교대 실행."
note ""

# ── 준비: 게이트웨이 설치 (이후 두 arm 내내 유지) ─────────────────────
log "agentgateway v1.4.1 설치 (두 arm 내내 유지)"
AGW_VER=v1.4.1 bash "$GWDIR/install.sh" > "$OUT/install.log" 2>&1
sleep 30
kubectl --context $CTX apply -f "$GWDIR/gateway.yaml" >> "$OUT/install.log" 2>&1
kubectl --context $CTX -n $NS scale deploy/mcp-a --replicas=1 >/dev/null 2>&1
kubectl --context $CTX -n $NS scale deploy/mcp-b --replicas=1 >/dev/null 2>&1
sleep 20
GW=$(kubectl --context $CTX -n agentgateway-system get gateway agentgateway-proxy -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
[ -z "$GW" ] && { log "[중단] 게이트웨이 주소 없음"; note "**중단**: 게이트웨이 주소 없음"; exit 1; }
DIRECT_URL="http://192.168.2.231/mcp"
GW_URL="http://$GW/b"
log "direct=$DIRECT_URL gw=$GW_URL"
note "- direct: \`$DIRECT_URL\` / gw: \`$GW_URL\` / 게이트웨이 파드 상주 확인:"
note '```'
kubectl --context $CTX -n agentgateway-system get pods >> "$OUT/FINDINGS.md" 2>/dev/null
note '```'
note ""

cell() { # cell <name> <url> <rps> <concurrency>
  "$PY" "$LOADGEN" --url "$2" --dialect b --tool echo \
    --concurrency "$4" --duration 30 --conn-mode close --rps "$3" \
    --out "$OUT/$1.json" >/dev/null 2>&1
  "$PY" -c "
import json
d=json.load(open('$OUT/$1.json'))
err=sum(d.get('errors', {}).values())
print(f\"achieved={d['achieved_rps']:.1f} p50={d['latency_ms']['p50']:.1f} p99={d['latency_ms']['p99']:.1f} err={err}\")"
}

# ── 본 측정: rps별 5회, 회차 안에서 direct -> gw 교대 ─────────────────
for rps in 100 200; do
  conc=8; [ "$rps" = 200 ] && conc=16
  note "## ${rps}rps (concurrency $conc)"
  note ""
  for n in 1 2 3 4 5; do
    log "=== ${rps}rps rep$n: direct ==="
    R=$(cell "ab-direct-rps${rps}-n${n}" "$DIRECT_URL" "$rps" "$conc")
    note "- direct n$n: $R"
    sleep $COOLDOWN
    log "=== ${rps}rps rep$n: gw ==="
    R=$(cell "ab-gw-rps${rps}-n${n}" "$GW_URL" "$rps" "$conc")
    note "- gw     n$n: $R"
    sleep $COOLDOWN
  done
  note ""
done

# ── 정리 ─────────────────────────────────────────────────────────────
log "정리: agentgateway 제거 (격리 복원)"
bash "$GWDIR/uninstall.sh" >> "$OUT/install.log" 2>&1
note "---"
note "정리 완료. 게이트웨이를 제거해 격리 상태로 되돌렸다."
log "=== A/B 측정 완료: $OUT ==="
