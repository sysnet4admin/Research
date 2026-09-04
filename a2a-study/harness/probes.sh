#!/usr/bin/env bash
# 축 A(카드 매트릭스)와 축 B(관측) 결정론 프로브. DESIGN.md 참조.
# 종료 시 게이트웨이와 에이전트를 남겨 둔다(축 C ab_matrix.sh가 이어받고
# 최종 정리도 거기서 한다).
# 사용: ./probes.sh <OUT_BASE>   (예: runs/probes-0827)
set -uo pipefail

BASE="$1"; CTX="mcp-migration"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
REPO="$(cd "$STUDY/.." && pwd)"
GWDIR="$REPO/mcp-migration/studies/stateless-scaleout/k8s/agentgateway"
mkdir -p "$STUDY/$BASE"; OUT="$STUDY/$BASE"
log() { echo "[$(date '+%m-%d %H:%M')] $*"; }
note() { echo "$*" >> "$OUT/FINDINGS.md"; }

echo "# A2A 본측정 프로브: 축 A 카드 매트릭스 + 축 B 관측 (자동 생성)" > "$OUT/FINDINGS.md"
note ""
note "시작 $(date '+%Y-%m-%d %H:%M'). 호스트 M4, agentgateway v1.4.1."
note ""

log "게이트웨이 설치"
AGW_VER=v1.4.1 bash "$GWDIR/install.sh" > "$OUT/install.log" 2>&1
sleep 30
kubectl --context $CTX apply -f "$GWDIR/gateway.yaml" >> "$OUT/install.log" 2>&1
sleep 15
GW=$(kubectl --context $CTX -n agentgateway-system get gateway agentgateway-proxy -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
[ -z "$GW" ] && { note "**중단**: 게이트웨이 주소 없음"; exit 1; }
GW="http://$GW"
note "- 게이트웨이: $GW"

log "에이전트 배포"
kubectl --context $CTX -n $NS delete configmap a2a-echo-code >/dev/null 2>&1
kubectl --context $CTX -n $NS create configmap a2a-echo-code \
  --from-file="$STUDY/k8s/server.py" >> "$OUT/install.log" 2>&1
kubectl --context $CTX apply -f "$STUDY/k8s/agent.yaml" >> "$OUT/install.log" 2>&1
kubectl --context $CTX -n $NS rollout status deploy/a2a-echo --timeout=300s >> "$OUT/install.log" 2>&1
for i in $(seq 1 30); do
  LB=$(kubectl --context $CTX -n $NS get svc a2a-echo-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  [ -n "$LB" ] && break; sleep 2
done
[ -z "$LB" ] && { note "**중단**: LB 주소 없음"; exit 1; }
DIRECT="http://$LB:9999"
note "- direct(LB): $DIRECT"
note ""

send() { # send <url> <method> <extra-curl-args...>
  local url="$1" method="$2"; shift 2
  curl -s --max-time 10 -X POST "$url" -H 'Content-Type: application/json' "$@" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$method\",\"params\":{\"message\":{\"kind\":\"message\",\"role\":\"user\",\"messageId\":\"p-1\",\"parts\":[{\"kind\":\"text\",\"text\":\"ping\"}],\"metadata\":{\"probe\":\"$method\"}}}}"
}

log "축 A: 카드 매트릭스 (형식 3 x 경로 3)"
note "## 축 A: 카드 매트릭스"
note ""
for fmt in v03 v10 both; do
  kubectl --context $CTX -n $NS set env deploy/a2a-echo CARD_FORMAT=$fmt >> "$OUT/install.log" 2>&1
  kubectl --context $CTX -n $NS rollout status deploy/a2a-echo --timeout=120s >> "$OUT/install.log" 2>&1
  sleep 5
  curl -s --max-time 10 "$GW/agent/.well-known/agent.json" > "$OUT/card-gw-a2a-$fmt.json"
  curl -s --max-time 10 "$GW/agent-plain/.well-known/agent.json" > "$OUT/card-gw-plain-$fmt.json"
  curl -s --max-time 10 "$DIRECT/.well-known/agent.json" > "$OUT/card-direct-$fmt.json"
  note "- 형식 $fmt: 카드 3장 수집 (gw-a2a, gw-plain, direct)"
done
kubectl --context $CTX -n $NS set env deploy/a2a-echo CARD_FORMAT=v03 >> "$OUT/install.log" 2>&1
kubectl --context $CTX -n $NS rollout status deploy/a2a-echo --timeout=120s >> "$OUT/install.log" 2>&1
sleep 5
note ""

log "축 A: 우회 실증 (direct message/send x5)"
note "## 축 A: 우회 실증 (게이트웨이 미경유 직접 호출)"
note ""
for n in 1 2 3 4 5; do
  send "$DIRECT/" message/send > "$OUT/bypass-$n.json"
  R=$(python3 -c "import json;d=json.load(open('$OUT/bypass-$n.json'));print(d.get('result',{}).get('parts',[{}])[0].get('text','FAIL'))" 2>/dev/null)
  note "- n$n: $R"
done
note ""

log "축 B: traceparent 프로브"
note "## 축 B: traceparent (수신 헤더는 에이전트가 응답 metadata로 반사)"
note ""
TID="4bf92f3577b34da6a3ce929d0e0e4736"
for n in 1 2 3 4 5; do
  send "$GW/agent" message/send -H "traceparent: 00-$TID-00f067aa0ba902b$n-01" > "$OUT/trace-with-$n.json"
  send "$GW/agent" message/send > "$OUT/trace-none-$n.json"
  send "$DIRECT/" message/send -H "traceparent: 00-$TID-00f067aa0ba902b$n-01" > "$OUT/trace-direct-$n.json"
done
for kind in with none direct; do
  note "- trace-$kind 수신값:"
  for n in 1 2 3 4 5; do
    R=$(python3 -c "
import json
d=json.load(open('$OUT/trace-$kind-$n.json'))
m=d.get('result',{}).get('metadata',{})
print('tp=', m.get('received_headers',{}).get('traceparent'), ' msg_meta=', m.get('received_message_metadata'))" 2>/dev/null)
    note "  - n$n: $R"
  done
done
note ""

log "축 B: 오류 형태 (미지원 메서드)"
note "## 축 B: 오류 형태 (tasks/get -> 에이전트 -32601)"
note ""
for n in 1 2 3; do
  send "$GW/agent" tasks/get > "$OUT/err-unknown-gw-$n.json"
done
send "$DIRECT/" tasks/get > "$OUT/err-unknown-direct-1.json"
for f in err-unknown-gw-1 err-unknown-gw-2 err-unknown-gw-3 err-unknown-direct-1; do
  note "- $f: $(cat "$OUT/$f.json")"
done
note ""

log "프록시 로그 캡처"
# 파드 전체 로그를 뜬다. --since-time은 시간대 없는 값이면 kubectl이 거부해
# 캡처가 조용히 0건이 된다(probes-0827 사고). 프록시 파드는 이 스크립트의
# 설치 시점에 생기므로 전체 로그 = 이번 실행 범위다.
for p in $(kubectl --context $CTX -n agentgateway-system get pods -o name); do
  kubectl --context $CTX -n agentgateway-system logs "$p" 2>/dev/null
done > "$OUT/proxy-full.log"
grep -a 'protocol=a2a' "$OUT/proxy-full.log" > "$OUT/proxy-a2a.log"
note "## 프록시 로그"
note ""
note "- protocol=a2a 레코드 $(wc -l < "$OUT/proxy-a2a.log" | tr -d ' ')건 (proxy-a2a.log), 전체 proxy-full.log"
note ""
note "---"
note "종료 $(date '+%Y-%m-%d %H:%M'). 게이트웨이와 에이전트는 축 C(ab_matrix.sh)를"
note "위해 남겨 둠. 최종 정리는 ab_matrix.sh 종료부."
log "=== probes 완료 ==="
