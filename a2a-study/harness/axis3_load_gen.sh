#!/usr/bin/env bash
# 축 3 오버헤드(두 세대판): 같은 파드의 세 구현에 같은 부하를 걸고 A2A는 두 세대를 나란히 잰다.
# axis3_load.sh의 최소 델타 사본이다. 다른 것은 a2a 셀이 RV_GENS만큼 반복되는 것 하나다.
# 셀: rps x 모드 x 회차, 회차 안에서 http -> mcp -> a2a(세대별) 교대.
# 사용: ./axis3_load_gen.sh <PYTHON> <OUT_DIR>
# 조절: RV_ROUNDS(기본 5) RV_DURATION(30) RV_COOLDOWN(180) RV_RPS("50 100") RV_MODES("close reuse")
#       RV_GENS("0.3 1.0")
set -uo pipefail

PY="$1"; OUT_REL="$2"
CTX="aaif-benchmark"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
ROUNDS="${RV_ROUNDS:-5}"; DUR="${RV_DURATION:-30}"; COOLDOWN="${RV_COOLDOWN:-180}"
RPS_LIST="${RV_RPS:-50 100}"; MODES="${RV_MODES:-close reuse}"; GENS="${RV_GENS:-0.3 1.0}"
OUT="$STUDY/$OUT_REL"; mkdir -p "$OUT"
log() { echo "[axis3 $(date '+%m-%d %H:%M')] $*"; }
note() { echo "$*" >> "$OUT/FINDINGS.md"; }
cleanup() { kubectl --context $CTX delete -f "$STUDY/k8s/three-arms/three-arms.yaml" >/dev/null 2>&1
            kubectl --context $CTX -n $NS delete configmap three-arms-code >/dev/null 2>&1; log "정리 완료"; }
trap cleanup EXIT

log "세 구현 배포"
kubectl --context $CTX -n $NS delete configmap three-arms-code >/dev/null 2>&1
kubectl --context $CTX -n $NS create configmap three-arms-code \
  --from-file="$STUDY/k8s/three-arms/work.py" --from-file="$STUDY/k8s/three-arms/srv_a2a.py" \
  --from-file="$STUDY/k8s/three-arms/srv_mcp.py" --from-file="$STUDY/k8s/three-arms/srv_http.py" > "$OUT/apply.log" 2>&1
kubectl --context $CTX apply -f "$STUDY/k8s/three-arms/three-arms.yaml" >> "$OUT/apply.log" 2>&1
kubectl --context $CTX -n $NS rollout status deploy/three-arms --timeout=600s >> "$OUT/apply.log" 2>&1 \
  || { echo "**중단**: 세 구현 기동 실패" > "$OUT/FINDINGS.md"; exit 1; }
IP=$(kubectl --context $CTX -n $NS get svc three-arms -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
wait_port() { local i=0; until curl -s --max-time 3 -o /dev/null "http://$IP:$1$2"; do i=$((i+5)); [ $i -ge $3 ] && { log "포트 $1 대기 초과"; return 1; }; sleep 5; done; log "포트 $1 준비(${i}s)"; }
wait_port 9103 / 120 && wait_port 9102 /mcp 180 && wait_port 9101 /.well-known/agent-card.json 420 || { echo "**중단**: 포트 준비 실패" > "$OUT/FINDINGS.md"; exit 1; }
sleep 10

echo "# 축 3 오버헤드: 세 구현 같은 부하 (자동 생성)" > "$OUT/FINDINGS.md"
note ""
note "실행 $(date '+%Y-%m-%d %H:%M'). 파드 하나(컨테이너 3개, 같은 work.py), IP $IP."
note "셀 = ${DUR}초, 회차 ${ROUNDS}회, 쿨다운 ${COOLDOWN}초, rps {$RPS_LIST}, 모드 {$MODES}, a2a 세대 {$GENS}."
note "회차 안에서 http -> mcp -> a2a(세대별) 교대."
note "생성기는 harness/loadgen3.py 하나(구현별로 요청 구성과 성공 판정만 다름)."
note ""
url_of() { case "$1" in http) echo "http://$IP:9103/";; mcp) echo "http://$IP:9102/mcp";; a2a) echo "http://$IP:9101/a2a/jsonrpc";; esac; }
cell() { # cell <tag> <arm> <mode> <rps> <conc> [gen]
  "$PY" "$DIR/loadgen3.py" --url "$(url_of "$2")" --arm "$2" --concurrency "$5" --duration "$DUR" \
    --conn-mode "$3" --rps "$4" ${6:+--gen "$6"} --out "$OUT/$1.json" >/dev/null 2>&1
  "$PY" -c "
import json
d=json.load(open('$OUT/$1.json'))
err=sum(d.get('errors', {}).values()); ok=d['ok'] or 1
print(f\"achieved={d['achieved_rps']:.1f} p50={d['latency_ms']['p50']} p99={d['latency_ms']['p99']} err={err} shed={d.get('shed')} bytes/ok={d.get('resp_bytes_total',0)//ok}\")"
}
for rps in $RPS_LIST; do
  conc=8; [ "$rps" -ge 100 ] && conc=16
  for mode in $MODES; do
    note "## ${rps}rps, $mode 모드 (concurrency $conc)"
    note ""
    for n in $(seq 1 "$ROUNDS"); do
      for arm in http mcp a2a; do
        if [ "$arm" = "a2a" ]; then
          for g in $GENS; do
            log "${rps}rps $mode rep$n: a2a v$g"
            note "- a2a(v$g) n$n: $(cell "ax3-a2a-v$g-$mode-rps$rps-n$n" a2a "$mode" "$rps" "$conc" "$g")"
            sleep "$COOLDOWN"
          done
        else
          log "${rps}rps $mode rep$n: $arm"
          note "- $arm n$n: $(cell "ax3-$arm-$mode-rps$rps-n$n" "$arm" "$mode" "$rps" "$conc")"
          sleep "$COOLDOWN"
        fi
      done
    done
    note ""
  done
done
note "컨테이너 로그(마지막 3줄씩):"
note '```'
for c in http mcp a2a; do echo "-- $c"; kubectl --context $CTX -n $NS logs deploy/three-arms -c $c --tail=3 2>&1; done >> "$OUT/FINDINGS.md"
note '```'
log "=== 축 3 완료: $OUT ==="
