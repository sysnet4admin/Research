#!/usr/bin/env bash
# 대안 대비의 A2A 값을 v1.0 세대로 다시 잰다.
# axis2_scenarios.sh가 v0.3 형식(message/send, 헤더 없음)으로 쟀기 때문에 같은 항목을
# A2A-Version: 1.0 + v1.0 메서드 이름으로 다시 재서 두 세대의 바이트를 나란히 둔다.
# 재는 것: 짧은 작업 응답, 폴링 1회, 스트리밍 이벤트 합, 푸시 두 요청 합, 카드.
# 사용: ./axis2_v10_bytes.sh <OUT_DIR>
set -uo pipefail
OUT_REL="${1:-runs/axis2v10-$(date +%m%d)}"
CTX="aaif-benchmark"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
OUT="$STUDY/$OUT_REL"; mkdir -p "$OUT"
F="$OUT/FINDINGS.md"
log() { echo "[v10 $(date '+%m-%d %H:%M')] $*"; }
note() { echo "$*" >> "$F"; }

kubectl --context $CTX get nodes >/dev/null 2>&1 || { log "중단: 클러스터 접근 불가"; exit 1; }

cleanup() { [ "${KEEP:-0}" = "1" ] || { kubectl --context $CTX delete -f "$STUDY/k8s/axis2/axis2-arms.yaml" >/dev/null 2>&1
          kubectl --context $CTX -n $NS delete configmap axis2-code >/dev/null 2>&1; log "정리 완료"; }; }
trap cleanup EXIT

log "대안 대비 서버 배포"
kubectl --context $CTX -n $NS delete configmap axis2-code >/dev/null 2>&1
kubectl --context $CTX -n $NS create configmap axis2-code \
  --from-file="$STUDY/k8s/axis2/work.py" --from-file="$STUDY/k8s/axis2/srv_a2a.py" \
  --from-file="$STUDY/k8s/axis2/srv_mcp.py" --from-file="$STUDY/k8s/axis2/srv_http.py" > "$OUT/apply.log" 2>&1
kubectl --context $CTX apply -f "$STUDY/k8s/axis2/axis2-arms.yaml" >> "$OUT/apply.log" 2>&1
kubectl --context $CTX -n $NS rollout status deploy/axis2-arms --timeout=600s >> "$OUT/apply.log" 2>&1 \
  || { echo "**중단**: 기동 실패" > "$F"; exit 1; }
IP=$(kubectl --context $CTX -n $NS get svc axis2-arms -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
for i in $(seq 1 60); do curl -s --max-time 3 -o /dev/null "http://$IP:9101/.well-known/agent-card.json" && break; sleep 5; done
sleep 5
log "IP $IP"

B="http://$IP:9101/a2a/jsonrpc"
H10=(-H 'Content-Type: application/json' -H 'A2A-Version: 1.0')
H03=(-H 'Content-Type: application/json')
# post <tag> <헤더배열이름> <본문> -> "코드 시간 업로드 다운로드"
post() { local tag=$1 gen=$2 body=$3; local -n H="$gen"
  curl -s --max-time 90 -o "$OUT/$tag.res" -w "%{http_code} %{time_total} %{size_upload} %{size_download}" \
    -X POST "$B" "${H[@]}" -d "$body"; }
jq_() { python3 -c "
import json,sys
d=json.load(open('$OUT/$1.res'))
$2" 2>/dev/null || echo "(파싱 실패)"; }

echo "# 대안 대비 A2A: 두 세대 바이트 비교 (자동 생성)" > "$F"
note ""
note "실행 $(date '+%Y-%m-%d %H:%M'). 서버 \`k8s/axis2/\`, IP $IP."
note "v0.3은 헤더 없이 \`message/send\`, v1.0은 \`A2A-Version: 1.0\`과 \`SendMessage\`로 보냈다."
note ""

# 1. 짧은 작업 응답 바이트
log "짧은 작업"
M03='{"jsonrpc":"2.0","id":1,"method":"message/send","params":{"message":{"kind":"message","role":"user","messageId":"b1","parts":[{"kind":"text","text":"fast:hello-world"}]}}}'
M10='{"jsonrpc":"2.0","id":1,"method":"SendMessage","params":{"message":{"role":"ROLE_USER","messageId":"b1","parts":[{"text":"fast:hello-world"}]}}}'
r03=$(post short03 H03 "$M03"); r10=$(post short10 H10 "$M10")
note "## 짧은 작업 응답 1건"
note ""
note "- v0.3: $(echo $r03 | cut -d' ' -f4) 바이트 (HTTP $(echo $r03 | cut -d' ' -f1))"
note "- v1.0: $(echo $r10 | cut -d' ' -f4) 바이트 (HTTP $(echo $r10 | cut -d' ' -f1))"
note ""

# 2. 장시간 작업 시작과 폴링 1회
log "폴링"
L03='{"jsonrpc":"2.0","id":1,"method":"message/send","params":{"message":{"kind":"message","role":"user","messageId":"L1","parts":[{"kind":"text","text":"hello-world"}]},"configuration":{"blocking":false}}}'
# v1.0에는 blocking이 없고 returnImmediately가 그 자리다(실측으로 확인).
L10='{"jsonrpc":"2.0","id":1,"method":"SendMessage","params":{"message":{"role":"ROLE_USER","messageId":"L1","parts":[{"text":"hello-world"}]},"configuration":{"returnImmediately":true}}}'
# 두 세대를 순차로 돈다. 동시에 시작하면 앞 세대를 폴링하는 동안 뒤 세대가
# 이미 끝나서 폴링 횟수가 1회로 나온다(첫 실행에서 실제로 그렇게 됐다).
s03=$(post start03 H03 "$L03"); T03=$(jq_ start03 "print(d['result']['id'])")
log "태스크 v0.3=$T03"
# 완료까지 1초 간격으로 폴링한다. 발행본이 "폴링 15회 뒤 completed"를 기준으로 잰 값이라
# 같은 기준으로 맞춘다. 회차별 바이트를 모두 남기고 평균과 마지막을 따로 보고한다.
poll_until() { # poll_until <gen> <method> <taskid> <prefix> -> "회수 합 마지막"
  local gen=$1 method=$2 tid=$3 pre=$4 n=0 sum=0 last=0 st=""
  for i in $(seq 1 30); do
    n=$((n+1))
    local r; r=$(post "$pre$n" "$gen" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$method\",\"params\":{\"id\":\"$tid\"}}")
    last=$(echo $r | cut -d' ' -f4); sum=$((sum+last))
    st=$(python3 -c "
import json
d=json.load(open('$OUT/$pre$n.res'))
r=d.get('result') or {}
t=r.get('task') or r
print(((t.get('status') or {}).get('state') or '').lower())
" 2>/dev/null)
    case "$st" in *completed*) break;; esac
    sleep 1
  done
  echo "$n $sum $last $st"
}
log "v0.3 폴링"
r03=$(poll_until H03 "tasks/get" "$T03" "poll03-")
s10=$(post start10 H10 "$L10"); T10=$(jq_ start10 "print(d['result']['task']['id'])")
log "태스크 v1.0=$T10"
log "v1.0 폴링"
r10=$(poll_until H10 "GetTask" "$T10" "poll10-")
n03=$(echo $r03|cut -d' ' -f1); s03t=$(echo $r03|cut -d' ' -f2); l03=$(echo $r03|cut -d' ' -f3)
n10=$(echo $r10|cut -d' ' -f1); s10t=$(echo $r10|cut -d' ' -f2); l10=$(echo $r10|cut -d' ' -f3)
note "## 장시간 작업 시작 응답"
note ""
note "- v0.3: $(echo $s03 | cut -d' ' -f4) 바이트"
note "- v1.0: $(echo $s10 | cut -d' ' -f4) 바이트"
note ""
note "## 폴링 (1초 간격, 완료까지)"
note ""
note "| 세대 | 확인 횟수 | 합계 바이트 | 1회 평균 | 완료 응답 |"
note "|---|---|---|---|---|"
note "| v0.3 | $n03 | $s03t | $((s03t / n03)) | $l03 |"
note "| v1.0 | $n10 | $s10t | $((s10t / n10)) | $l10 |"
note ""
note "발행본의 571바이트는 완료 응답 기준이다. 진행 중 응답은 이력이 덜 쌓여 더 작다."
note ""

# 3. 스트리밍 이벤트 합
log "스트리밍"
S03='{"jsonrpc":"2.0","id":1,"method":"message/stream","params":{"message":{"kind":"message","role":"user","messageId":"S1","parts":[{"kind":"text","text":"hello-world"}]}}}'
S10='{"jsonrpc":"2.0","id":1,"method":"SendStreamingMessage","params":{"message":{"role":"ROLE_USER","messageId":"S1","parts":[{"text":"hello-world"}]}}}'
b03=$(curl -s --max-time 60 -N -X POST "$B" "${H03[@]}" -d "$S03" | wc -c | tr -d ' ')
b10=$(curl -s --max-time 60 -N -X POST "$B" "${H10[@]}" -d "$S10" | wc -c | tr -d ' ')
note "## 스트리밍 (SSE 본문 전체)"
note ""
note "- v0.3 \`message/stream\`: $b03 바이트"
note "- v1.0 \`SendStreamingMessage\`: $b10 바이트"
note ""

# 4. 카드 (버전 무관 확인)
c=$(curl -s -o "$OUT/card.json" -w "%{size_download}" "http://$IP:9101/.well-known/agent-card.json")
note "## 에이전트 카드"
note ""
note "- 카드 1회: $c 바이트 (버전 헤더와 무관)"
note ""
note "원자료는 이 디렉터리의 \`*.res\`에 있다."
log "=== 완료: $OUT ==="
