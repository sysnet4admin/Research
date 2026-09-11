#!/usr/bin/env bash
# tail 보강 (2026-09-03): 게이트웨이 홉이 꼬리(p99)에 주는 영향을 백엔드 처리
# 시간과 부하 지속 시간의 함수로 잰다. rv_run_ab.sh/rv_run_abr.sh의 최소 델타 확장.
#   축 1. 지연 스윕: B_DELAY_MS in RV_DELAYS x {close, reuse} x 회차 RV_ROUNDS,
#         회차 안 direct -> gw 교대, 100rps RV_DURATION초 셀.
#   축 2. 지속 창: B_DELAY_MS=RV_SUSTAIN_DELAY 고정, RV_SUSTAIN초 연속 x
#         {close, reuse} x {direct, gw}, 순서 뒤집어 RV_SUSTAIN_REPS회.
# 백엔드 코드 = k8s/b-server-delay/server.py (ConfigMap 교체 + env 롤아웃, 이미지 빌드 없음).
# 종료 시 원본 ConfigMap과 env 없음 상태로 복원한다.
# 사용: ./rv_tail.sh <PYTHON> <OUT_DIR>
set -uo pipefail

PY="$1"; OUT="$2"
CTX="aaif-benchmark"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
REPO="$(cd "$STUDY/.." && pwd)"
MCPSTUDY="$REPO/mcp-migration/studies/stateless-scaleout"
LOADGEN="$MCPSTUDY/harness/loadgen.py"
ORIG_SERVER="$MCPSTUDY/b-server/server.py"
DELAY_SERVER="$STUDY/k8s/b-server-delay/server.py"
DURATION="${RV_DURATION:-30}"
CD_CLOSE="${RV_COOLDOWN_CLOSE:-180}"
CD_REUSE="${RV_COOLDOWN_REUSE:-60}"
ROUNDS="${RV_ROUNDS:-5}"
DELAYS="${RV_DELAYS:-0 10 50 200}"
SUSTAIN="${RV_SUSTAIN:-1800}"
SUSTAIN_DELAY="${RV_SUSTAIN_DELAY:-50}"
SUSTAIN_REPS="${RV_SUSTAIN_REPS:-2}"
RPS=100
mkdir -p "$OUT"

log() { echo "[$(date '+%m-%d %H:%M')] $*"; }
note() { echo "$*" >> "$OUT/FINDINGS.md"; }
conc_for() { # 100rps x 지연에 맞는 동시성 (in-flight = rps x delay, 2배 여유)
  case "$1" in 0|10) echo 8;; 50) echo 16;; 200) echo 40;; *) echo 16;; esac
}
set_delay() { # ConfigMap(지연판 코드) + env 롤아웃
  kubectl --context $CTX -n $NS create configmap b-server-code --from-file=server.py="$DELAY_SERVER" \
    --dry-run=client -o yaml | kubectl --context $CTX apply -f - >/dev/null 2>&1
  kubectl --context $CTX -n $NS set env deploy/mcp-b B_DELAY_MS="$1" >/dev/null 2>&1
  kubectl --context $CTX -n $NS rollout restart deploy/mcp-b >/dev/null 2>&1
  kubectl --context $CTX -n $NS rollout status deploy/mcp-b --timeout=180s >/dev/null 2>&1 || return 1
  sleep 10
}
restore_backend() {
  kubectl --context $CTX -n $NS create configmap b-server-code --from-file=server.py="$ORIG_SERVER" \
    --dry-run=client -o yaml | kubectl --context $CTX apply -f - >/dev/null 2>&1
  kubectl --context $CTX -n $NS set env deploy/mcp-b B_DELAY_MS- >/dev/null 2>&1
  kubectl --context $CTX -n $NS rollout restart deploy/mcp-b >/dev/null 2>&1
  kubectl --context $CTX -n $NS rollout status deploy/mcp-b --timeout=180s >/dev/null 2>&1
}
cell() { # cell <name> <url> <mode> <concurrency> <duration>
  "$PY" "$LOADGEN" --url "$2" --dialect b --tool echo \
    --concurrency "$4" --duration "$5" --conn-mode "$3" --rps "$RPS" \
    --out "$OUT/$1.json" >/dev/null 2>&1
  "$PY" -c "
import json
d=json.load(open('$OUT/$1.json'))
err=sum(d.get('errors', {}).values())
print(f\"achieved={d['achieved_rps']:.1f} p50={d['latency_ms']['p50']:.1f} p99={d['latency_ms']['p99']:.1f} err={err} shed={d.get('shed',0)}\")"
}
cooldown() { [ "$1" = close ] && sleep "$CD_CLOSE" || sleep "$CD_REUSE"; }

# ── 전제 ──────────────────────────────────────────────────────────────
"$PY" -c "import httpx" 2>/dev/null || { log "[중단] venv httpx 없음"; exit 1; }
GW=$(kubectl --context $CTX -n agentgateway-system get gateway agentgateway-proxy -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
[ -z "$GW" ] && { log "[중단] 게이트웨이 주소 없음"; exit 1; }
DIRECT_URL="http://$(kubectl --context $CTX -n $NS get svc mcp-b -o jsonpath='{.status.loadBalancer.ingress[0].ip}')/mcp"
GW_URL="http://$GW/b"
AGWV=$(kubectl --context $CTX -n agentgateway-system get deploy agentgateway-proxy -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | sed 's/.*://')

echo "# tail 보강: 백엔드 지연 스윕 + 지속 창 (자동 생성, agentgateway $AGWV)" > "$OUT/FINDINGS.md"
note ""
note "실행 $(date '+%Y-%m-%d %H:%M'). 컨텍스트 $CTX. direct=\`$DIRECT_URL\` gw=\`$GW_URL\`."
note "게이트웨이 상주(정책 0), 두 경로의 차이는 대상 주소뿐. ${RPS}rps 열린 루프."
note "축 1: 지연 {${DELAYS}}ms x {close, reuse} x 회차 ${ROUNDS}, ${DURATION}초 셀, 쿨다운 close ${CD_CLOSE}s / reuse ${CD_REUSE}s."
note "축 2: 지연 ${SUSTAIN_DELAY}ms 고정, ${SUSTAIN}초 연속 x {close, reuse} x {direct, gw}, 순서 뒤집어 ${SUSTAIN_REPS}회."
note "- 전원: $(pmset -g batt | head -1 | sed "s/Now drawing from //")"
note ""

# ── 축 1: 지연 스윕 (RV_SKIP_SWEEP=1이면 건너뜀: 지속 창 전용 실행) ────
[ "${RV_SKIP_SWEEP:-0}" = 1 ] && DELAYS=""
note "## 축 1. 백엔드 지연 스윕 (교대 순서 그대로)"
note ""
for d in $DELAYS; do
  log "=== 지연 ${d}ms 롤아웃 ==="
  set_delay "$d" || { log "[중단] 롤아웃 실패(지연 $d)"; note "**중단**: 롤아웃 실패(지연 $d)"; restore_backend; exit 1; }
  conc=$(conc_for "$d")
  note "### 지연 ${d}ms (concurrency $conc)"
  for mode in close reuse; do
    for n in $(seq 1 "$ROUNDS"); do
      log "=== d${d} ${mode} n${n}: direct ==="
      R=$(cell "tail-d${d}-${mode}-direct-n${n}" "$DIRECT_URL" "$mode" "$conc" "$DURATION")
      note "  - d${d} ${mode} direct n${n}: $R"
      cooldown "$mode"
      log "=== d${d} ${mode} n${n}: gw ==="
      R=$(cell "tail-d${d}-${mode}-gw-n${n}" "$GW_URL" "$mode" "$conc" "$DURATION")
      note "  - d${d} ${mode} gw     n${n}: $R"
      cooldown "$mode"
    done
  done
  note ""
done

# ── 축 2: 지속 창 ─────────────────────────────────────────────────────
note "## 축 2. 지속 창 ${SUSTAIN}초, 지연 ${SUSTAIN_DELAY}ms"
note ""
log "=== 지속 창: 지연 ${SUSTAIN_DELAY}ms 롤아웃 ==="
set_delay "$SUSTAIN_DELAY" || { log "[중단] 롤아웃 실패(지속)"; restore_backend; exit 1; }
conc=$(conc_for "$SUSTAIN_DELAY")
for rep in $(seq 1 "$SUSTAIN_REPS"); do
  if [ $((rep % 2)) -eq 1 ]; then order="direct gw"; else order="gw direct"; fi
  for mode in close reuse; do
    for arm in $order; do
      url="$DIRECT_URL"; [ "$arm" = gw ] && url="$GW_URL"
      log "=== 지속 ${mode} rep${rep}: ${arm} (${SUSTAIN}s) ==="
      R=$(cell "sustain-d${SUSTAIN_DELAY}-${mode}-${arm}-r${rep}" "$url" "$mode" "$conc" "$SUSTAIN")
      note "  - sustain ${mode} ${arm} r${rep}: $R"
      cooldown "$mode"
    done
  done
done

# ── 복원 ─────────────────────────────────────────────────────────────
log "백엔드 원본 복원"
restore_backend
note ""
note "---"
note "종료 $(date '+%Y-%m-%d %H:%M'). 백엔드 코드와 env를 원본으로 복원했다(게이트웨이 상주)."
log "=== tail 보강 완료: $OUT ==="
