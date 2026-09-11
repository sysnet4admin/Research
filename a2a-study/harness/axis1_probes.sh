#!/usr/bin/env bash
# 축 1 본측정: 선언 대 실제. 스펙 v1.0.1의 MUST/SHOULD를 공식 파이썬 SDK 1.1.2의
# 기본 구성에 대고 항목 12개로 확인한다. 항목 번호는 README의 선언 대 실제 표를 따른다.
# 스파이크 2/3/4의 프로브를 합치고 "본측정에서 할 일"을 더한 것이다.
# 사용: ./axis1_probes.sh   (서버는 스스로 올리고 KEEP=1이면 남긴다)
set -uo pipefail
CTX="aaif-benchmark"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${OUT:-$DIR/runs/axis1-$(date +%m%d)}"; mkdir -p "$OUT"
F="$OUT/FINDINGS.md"; note() { echo "$*" >> "$F"; }; log() { echo "[axis1 $(date '+%m-%d %H:%M:%S')] $*"; }
KEEP="${KEEP:-1}"
cleanup() { [ "$KEEP" = "1" ] && { log "서버 유지(KEEP=1)"; return; }
  kubectl --context $CTX delete -f "$DIR/k8s/axis1/axis1.yaml" >/dev/null 2>&1
  kubectl --context $CTX -n $NS delete configmap a2a-axis1-code >/dev/null 2>&1; log "정리 완료"; }
trap cleanup EXIT

log "서버 확인"
kubectl --context $CTX -n $NS create configmap a2a-axis1-code \
  --from-file=server_axis1.py="$DIR/k8s/axis1/server_axis1.py" --dry-run=client -o yaml \
  | kubectl --context $CTX apply -f - > "$OUT/apply.log" 2>&1
kubectl --context $CTX apply -f "$DIR/k8s/axis1/axis1.yaml" >> "$OUT/apply.log" 2>&1
kubectl --context $CTX -n $NS rollout status deploy/a2a-axis1 --timeout=600s >> "$OUT/apply.log" 2>&1 || { echo "**중단**: 서버 기동 실패" > "$F"; exit 1; }
kubectl --context $CTX -n $NS rollout status deploy/a2a-axis1-nc --timeout=600s >> "$OUT/apply.log" 2>&1
kubectl --context $CTX -n $NS rollout status deploy/webhook4 --timeout=300s >> "$OUT/apply.log" 2>&1 || log "경고: webhook4 없음(1-10 건너뜀)"
B="http://$(kubectl --context $CTX -n $NS get svc a2a-axis1-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):9999"
NC="http://$(kubectl --context $CTX -n $NS get svc a2a-axis1-nc-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):9999"
WH="http://webhook4.mcp-pilot.svc.cluster.local:8000/hook"
sleep 3

echo "# 축 1 결과: 선언 대 실제 (자동 생성)" > "$F"
note ""
note "실행 $(date '+%Y-%m-%d %H:%M'). SDK a2a-sdk==1.1.2, DefaultRequestHandler + InMemoryTaskStore."
note "서버 둘: compat 켬 \`$B\`(작업 15초), compat 끔 \`$NC\`(작업 3초). 스킴 3종 선언(apiKey, bearer, oauth2)."
note "게이트웨이는 거치지 않는다. 항목 번호는 README의 선언 대 실제 표를 따른다."
note ""

# ---- 공용 ----
jrpc() { local tag="$1" base="$2" m="$3" p="$4"; shift 4
  curl -s --max-time 60 -o "$OUT/$tag.json" -w "%{http_code}" -X POST "$base/a2a/jsonrpc" \
    -H 'Content-Type: application/json' "$@" -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$m\",\"params\":$p}"; }
get() { local tag="$1" base="$2" path="$3"; shift 3
  curl -s --max-time 30 -o "$OUT/$tag.json" -w "%{http_code}" "$base$path" "$@"; }
post() { local tag="$1" base="$2" path="$3" body="$4"; shift 4
  curl -s --max-time 60 -o "$OUT/$tag.json" -w "%{http_code}" -X POST "$base$path" \
    -H 'Content-Type: application/json' "$@" -d "$body"; }
show() { head -c "${2:-180}" "$OUT/$1.json" | tr '\n' ' '; }
py() { python3 -c "
import json,sys
try: d=json.load(open('$OUT/$1.json'))
except Exception as e: print('파싱 실패'); sys.exit()
$2"; }
tid() { py "$1" "r=d.get('result',d); print((r or {}).get('id') or (r or {}).get('taskId') or ((r or {}).get('task') or {}).get('id') or '')"; }
st() { py "$1" "r=d.get('result',d); print(((r or {}).get('status') or {}).get('state') or (r or {}).get('error') or '?')"; }
MSG='{"message":{"role":"user","messageId":"MID","parts":[{"kind":"text","text":"TEXT"}]}CFG}'
mkmsg() { echo "$MSG" | sed "s/MID/$1/; s/TEXT/$2/; s|CFG|${3:-}|"; }

# ---- 1-1 카드 경로 ----
log "1-1 카드 경로"
note "## 1-1. 카드 경로"; note ""
for p in "/.well-known/agent-card.json" "/.well-known/agent.json"; do
  t="c$(echo $p | tr -cd 'a-z')"; c=$(get "$t" "$B" "$p")
  note "- compat 켬 \`$p\`: HTTP $c$( [ "$c" = "200" ] && echo ", name=$(py $t "print(d.get('name'))")" )"
done
c=$(get c-nc "$NC" "/.well-known/agent-card.json"); note "- compat 끔 \`/.well-known/agent-card.json\`: HTTP $c"
note ""

# ---- 1-2 병기 필드 ----
log "1-2 병기 필드"
note "## 1-2. 병기 필드 (compat 끈 카드도 병기인가)"; note ""
for pair in "B:$B" "NC:$NC"; do
  lbl="${pair%%:*}"; base="${pair#*:}"; t="card-$lbl"
  get "$t" "$base" "/.well-known/agent-card.json" >/dev/null
  note "- $( [ "$lbl" = "B" ] && echo 'compat 켬' || echo 'compat 끔' ): $(py $t "
i=d.get('supportedInterfaces') or []
vers=sorted({x.get('protocolVersion') for x in i})
print(f\"url 필드={'있음' if d.get('url') else '없음'}, supportedInterfaces {len(i)}개(버전 {vers}), supportsAuthenticatedExtendedCard={d.get('supportsAuthenticatedExtendedCard')}\")")"
done
note ""

# ---- 1-3 스킴 종류별 강제 ----
log "1-3 스킴 종류별 강제"
note "## 1-3. securitySchemes 선언 대 강제 (스킴 3종)"; note ""
note "- 카드 선언: $(py card-B "print(list((d.get('securitySchemes') or {}).keys()))"), security=$(py card-B "print(d.get('security'))")"
M13=$(mkmsg s1 hello '')
c=$(jrpc sec-none "$B" "message/send" "$M13");            note "- 무인증 message/send: HTTP $c, state=$(st sec-none)"
c=$(jrpc sec-badkey "$B" "message/send" "$M13" -H 'X-API-Key: wrong');       note "- 틀린 apiKey: HTTP $c, state=$(st sec-badkey)"
c=$(jrpc sec-badbearer "$B" "message/send" "$M13" -H 'Authorization: Bearer wrong'); note "- 틀린 bearer 토큰: HTTP $c, state=$(st sec-badbearer)"
c=$(get sec-card-none "$B" "/.well-known/agent-card.json"); note "- 무인증 카드 조회: HTTP $c"
note ""

# ---- 1-4 확장 카드 ----
log "1-4 확장 카드"
note "## 1-4. 확장 카드의 신원 게이팅"; note ""
c=$(get ext-none "$B" "/a2a/rest/extendedAgentCard" -H 'A2A-Version: 1.0')
note "- 무인증 REST 조회: HTTP $c, 스킬=$(py ext-none "print([s.get('id') for s in d.get('skills',[])] if isinstance(d,dict) else d)")"
c=$(get ext-bad "$B" "/a2a/rest/extendedAgentCard" -H 'A2A-Version: 1.0' -H 'X-API-Key: wrong' -H 'Authorization: Bearer wrong')
note "- 틀린 자격 증명 둘을 붙인 조회: HTTP $c, 스킬=$(py ext-bad "print([s.get('id') for s in d.get('skills',[])] if isinstance(d,dict) else d)")"
note "- 공개 카드 스킬: $(py card-B "print([s.get('id') for s in d.get('skills',[])])")"
c=$(jrpc ext-rpc10 "$B" "GetExtendedAgentCard" '{}'); note "- JSON-RPC v1.0 이름: HTTP $c, $(show ext-rpc10 150)"
c=$(jrpc ext-rpc03 "$B" "agent/getAuthenticatedExtendedCard" '{}'); note "- JSON-RPC v0.3 이름: HTTP $c, 스킬=$(py ext-rpc03 "r=d.get('result',{});print([s.get('id') for s in r.get('skills',[])])")"
c=$(jrpc ext-nc "$NC" "agent/getAuthenticatedExtendedCard" '{}'); note "- compat 끈 서버에 v0.3 이름: HTTP $c, $(show ext-nc 150)"
note ""

# ---- 1-5 상태 전이 타이밍 ----
log "1-5 상태 전이 (15초 작업, 5회)"
note "## 1-5. 상태 전이 타이밍 (작업 15초, 비차단, 5회)"; note ""
note "각 회차에서 message/send 직후부터 0.5초 간격으로 tasks/get을 돌려 상태가 바뀐 시각을 적는다."
note ""
note '```'
for n in 1 2 3 4 5; do
  M=$(mkmsg "t$n" "timing$n" ',"configuration":{"blocking":false}')
  s0=$(python3 -c "import time;print(time.time())")
  jrpc "tm-send-$n" "$B" "message/send" "$M" >/dev/null
  T=$(tid "tm-send-$n"); first=$(st "tm-send-$n"); seen="$first"; line="회차 $n: send=$first"
  for i in $(seq 1 40); do
    jrpc "tm-get-$n" "$B" "tasks/get" "{\"id\":\"$T\"}" >/dev/null
    s=$(st "tm-get-$n")
    if [ "$s" != "$seen" ]; then
      el=$(python3 -c "import time;print(f'{time.time()-$s0:.1f}')")
      line="$line -> $s(${el}s)"; seen="$s"
      [ "$s" = "completed" ] || [ "$s" = "failed" ] || [ "$s" = "canceled" ] && break
    fi
    sleep 0.5
  done
  echo "$line" >> "$F"
done
note '```'
note ""

# ---- 1-6 input-required ----
log "1-6 input-required"
note "## 1-6. input-required 재개"; note ""
M=$(mkmsg i1 "ask about env" ',"configuration":{"blocking":false}')
c=$(jrpc inp-send "$B" "message/send" "$M"); T=$(tid inp-send)
sleep 2; c=$(jrpc inp-get "$B" "tasks/get" "{\"id\":\"$T\"}")
note "- 'ask' 메시지 2초 뒤 상태: $(st inp-get)"
R="{\"message\":{\"role\":\"user\",\"messageId\":\"i2\",\"taskId\":\"$T\",\"parts\":[{\"kind\":\"text\",\"text\":\"prod\"}]},\"configuration\":{\"blocking\":false}}"
c=$(jrpc inp-res "$B" "message/send" "$R"); sleep 3
c=$(jrpc inp-get2 "$B" "tasks/get" "{\"id\":\"$T\"}")
note "- 같은 taskId로 후속 메시지 뒤: $(st inp-get2), 아티팩트=$(py inp-get2 "r=d.get('result',d);print([''.join(p.get('text','') for p in a.get('parts',[])) for a in (r or {}).get('artifacts') or []])")"
note ""

# ---- 1-9 스트리밍 + 1-7 스트림 중 취소 ----
log "1-9 스트리밍, 1-7 취소"
note "## 1-9. 스트리밍 (SSE)"; note ""
M=$(mkmsg s9 "stream" '')
curl -s --max-time 45 -N -X POST "$B/a2a/jsonrpc" -H 'Content-Type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"message/stream\",\"params\":$M}" > "$OUT/stream.txt" 2>&1
note "- 이벤트 수: $(grep -c '^data:' "$OUT/stream.txt" 2>/dev/null || echo 0)"
note "- 첫 이벤트: $(grep -m1 '^data:' "$OUT/stream.txt" | head -c 220)"
note "- 마지막 이벤트: $(grep '^data:' "$OUT/stream.txt" | tail -1 | head -c 220)"
note ""
note "## 1-7. CancelTask (세 조건)"; note ""
M=$(mkmsg c1 "cancel-me" ',"configuration":{"blocking":false}')
jrpc can-send "$B" "message/send" "$M" >/dev/null; T=$(tid can-send); sleep 2
c=$(jrpc can-mid "$B" "tasks/cancel" "{\"id\":\"$T\"}"); note "- 진행 중 취소: HTTP $c, state=$(st can-mid)"
sleep 16; c=$(jrpc can-after "$B" "tasks/get" "{\"id\":\"$T\"}"); note "- 작업 시간 경과 뒤 상태: $(st can-after)"
M=$(mkmsg c2 "quick" '')
jrpc can-done "$NC" "message/send" "$M" >/dev/null; T2=$(tid can-done); sleep 5
c=$(jrpc can-done2 "$NC" "tasks/cancel" "{\"id\":\"$T2\"}"); note "- 완료된 태스크 취소: HTTP $c, $(show can-done2 150)"
M=$(mkmsg c3 "ask now" ',"configuration":{"blocking":false}')
jrpc can-inp "$B" "message/send" "$M" >/dev/null; T3=$(tid can-inp); sleep 2
c=$(jrpc can-inp2 "$B" "tasks/cancel" "{\"id\":\"$T3\"}"); note "- input-required 상태 취소: HTTP $c, state=$(st can-inp2)"
note ""

# ---- 1-8 GetTask / ListTasks ----
log "1-8 조회"
note "## 1-8. GetTask와 ListTasks"; note ""
c=$(jrpc list1 "$B" "tasks/list" '{}'); note "- \`tasks/list\` (JSON-RPC): HTTP $c, $(show list1 200)"
c=$(get list-rest "$B" "/a2a/rest/tasks" -H 'A2A-Version: 1.0'); note "- REST GET \`/a2a/rest/tasks\`: HTTP $c, $(py list-rest "
t=d.get('tasks') if isinstance(d,dict) else None
print(f'태스크 {len(t)}건, 키={sorted(d.keys())}' if t is not None else str(d)[:150])")"
c=$(get list-rest2 "$B" "/a2a/rest/tasks?pageSize=2" -H 'A2A-Version: 1.0'); note "- 같은 요청에 pageSize=2: HTTP $c, $(py list-rest2 "
t=d.get('tasks') if isinstance(d,dict) else None
print(f'태스크 {len(t)}건, nextPageToken={\"있음\" if d.get(\"nextPageToken\") else \"없음\"}' if t is not None else str(d)[:150])")"
note ""

# ---- 1-10 푸시 재시도와 수신기 장애 ----
log "1-10 푸시"
note "## 1-10. 푸시 알림 (발송기 배선됨)"; note ""
M=$(mkmsg p1 "push ok" ',"configuration":{"blocking":false}')
jrpc pu-send "$B" "message/send" "$M" >/dev/null; TP=$(tid pu-send)
c=$(jrpc pu-set "$B" "tasks/pushNotificationConfig/set" "{\"taskId\":\"$TP\",\"pushNotificationConfig\":{\"url\":\"$WH\",\"id\":\"ok1\",\"token\":\"axis1-token\"}}")
note "- 정상 수신기로 설정: HTTP $c"
sleep 18
note "- 수신기 로그(최근 4줄):"; note '```'
kubectl --context $CTX -n $NS logs deploy/webhook4 --tail=4 >> "$F" 2>&1
note '```'
M=$(mkmsg p2 "push dead" ',"configuration":{"blocking":false}')
jrpc pu-send2 "$B" "message/send" "$M" >/dev/null; TD=$(tid pu-send2)
c=$(jrpc pu-set2 "$B" "tasks/pushNotificationConfig/set" "{\"taskId\":\"$TD\",\"pushNotificationConfig\":{\"url\":\"http://no-such-host.mcp-pilot.svc.cluster.local:8000/hook\",\"id\":\"dead1\"}}")
note "- 없는 수신기 주소로 설정: HTTP $c (설정 시점에 도달 확인을 하는가)"
sleep 18
c=$(jrpc pu-task2 "$B" "tasks/get" "{\"id\":\"$TD\"}"); note "- 그 태스크의 최종 상태: $(st pu-task2) (발송 실패가 태스크에 영향을 주는가)"
note "- 서버 로그에서 발송 실패 흔적:"; note '```'
kubectl --context $CTX -n $NS logs deploy/a2a-axis1 --tail=200 2>/dev/null | grep -iE 'push|notif|no-such-host' | tail -6 >> "$F"
note '```'
note ""

# ---- 1-11 트랜스포트 동등성 ----
log "1-11 트랜스포트 동등성"
note "## 1-11. 트랜스포트 동등성 (같은 요청 3종)"; note ""
M11=$(mkmsg e1 "same" '')
c=$(jrpc eq-rpc "$B" "message/send" "$M11"); note "- JSON-RPC \`message/send\`: HTTP $c"
note '```'; head -c 400 "$OUT/eq-rpc.json" >> "$F"; note ""; note '```'
c=$(post eq-r10 "$B" "/a2a/rest/message:send" "$M11" -H 'A2A-Version: 1.0'); note "- REST v1.0 \`/a2a/rest/message:send\`: HTTP $c"
note '```'; head -c 400 "$OUT/eq-r10.json" >> "$F"; note ""; note '```'
c=$(post eq-r10n "$B" "/a2a/rest/message:send" "$M11"); note "- 같은 REST 요청에 버전 헤더 없음: HTTP $c, $(show eq-r10n 200)"
c=$(post eq-r03 "$B" "/a2a/rest/v1/message:send" "$M11"); note "- REST v0.3 \`/a2a/rest/v1/message:send\`: HTTP $c"
note '```'; head -c 400 "$OUT/eq-r03.json" >> "$F"; note ""; note '```'
c=$(post eq-nc03 "$NC" "/a2a/rest/v1/message:send" "$M11"); note "- compat 끈 서버의 REST v0.3 경로: HTTP $c, $(show eq-nc03 150)"
M11B='{"message":{"role":"ROLE_USER","messageId":"e2","parts":[{"text":"same"}]}}'
c=$(post eq-r10b "$B" "/a2a/rest/message:send" "$M11B" -H 'A2A-Version: 1.0'); note "- REST v1.0에 v1.0 형식(role=ROLE_USER, parts.text): HTTP $c, $(show eq-r10b 200)"
c=$(jrpc eq-rpcb "$B" "message/send" "$M11B"); note "- JSON-RPC에 v1.0 형식: HTTP $c, $(show eq-rpcb 200)"
note ""

# ---- 1-12 오류 표면 ----
log "1-12 오류 표면"
note "## 1-12. 오류 표면"; note ""
c=$(jrpc er-m "$B" "tasks/nope" '{}');                      note "- 미지원 메서드: HTTP $c, $(show er-m 200)"
c=$(jrpc er-t "$B" "tasks/get" '{"id":"no-such-task"}');    note "- 없는 taskId: HTTP $c, $(show er-t 200)"
c=$(jrpc er-p "$B" "tasks/get" '{}');                       note "- 필수 파라미터 누락: HTTP $c, $(show er-p 200)"
c=$(jrpc er-b "$B" "message/send" '{"message":{"role":"user","messageId":"x"}}'); note "- parts 없는 메시지: HTTP $c, $(show er-b 200)"
c=$(get er-rest "$B" "/a2a/rest/v1/tasks/no-such-task");     note "- REST v0.3 없는 task: HTTP $c, $(show er-rest 200)"
c=$(get er-rest10 "$B" "/a2a/rest/tasks/no-such-task" -H 'A2A-Version: 1.0'); note "- REST v1.0 없는 task: HTTP $c, $(show er-rest10 200)"
EXT='{"message":{"role":"user","messageId":"x1","parts":[{"kind":"text","text":"hi"}],"extensions":["https://example.com/ext/does-not-exist"]}}'
c=$(jrpc er-ext "$B" "message/send" "$EXT");                note "- 선언하지 않은 확장을 실은 메시지: HTTP $c, state=$(st er-ext)"
note ""

note "## 서버 로그(마지막 20줄)"; note '```'
kubectl --context $CTX -n $NS logs deploy/a2a-axis1 --tail=20 >> "$F" 2>&1
note '```'
log "=== 축 1 완료: $F ==="
