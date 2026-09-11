#!/usr/bin/env bash
# 축 2 본측정: 대안 대비. 같은 work()를 세 구현(A2A, MCP, HTTP)이 부르고 클라이언트가
# 치르는 비용을 센다. 결과는 README의 대안 대비 절.
#   시나리오 1  짧은 작업(1초 안). 왕복 수, 바이트, 지연, 클라이언트가 알아야 하는 것, 실패 표면.
#   시나리오 2  오래 걸리는 작업(15초). 진행 확인과 취소를 각 구현의 관용대로 만들고 비교.
# 사용: ./axis2_scenarios.sh   (서버는 스스로 올리고 KEEP=1이면 남긴다)
set -uo pipefail
CTX="aaif-benchmark"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${OUT:-$DIR/runs/axis2-$(date +%m%d)}"; mkdir -p "$OUT"
F="$OUT/FINDINGS.md"; note() { echo "$*" >> "$F"; }; log() { echo "[axis2 $(date '+%m-%d %H:%M:%S')] $*"; }
KEEP="${KEEP:-1}"; REPS="${REPS:-5}"
cleanup() { [ "$KEEP" = "1" ] && { log "서버 유지(KEEP=1)"; return; }
  kubectl --context $CTX delete -f "$DIR/k8s/axis2/axis2-arms.yaml" >/dev/null 2>&1
  kubectl --context $CTX -n $NS delete configmap axis2-code >/dev/null 2>&1; log "정리 완료"; }
trap cleanup EXIT

log "서버 확인"
kubectl --context $CTX -n $NS create configmap axis2-code \
  --from-file=work.py="$DIR/k8s/axis2/work.py" --from-file=srv_a2a.py="$DIR/k8s/axis2/srv_a2a.py" \
  --from-file=srv_mcp.py="$DIR/k8s/axis2/srv_mcp.py" --from-file=srv_http.py="$DIR/k8s/axis2/srv_http.py" \
  --dry-run=client -o yaml | kubectl --context $CTX apply -f - > "$OUT/apply.log" 2>&1
kubectl --context $CTX apply -f "$DIR/k8s/axis2/axis2-arms.yaml" >> "$OUT/apply.log" 2>&1
kubectl --context $CTX -n $NS rollout status deploy/axis2-arms --timeout=600s >> "$OUT/apply.log" 2>&1 || { echo "**중단**: 기동 실패" > "$F"; exit 1; }
IP=$(kubectl --context $CTX -n $NS get svc axis2-arms -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
for p in 9101 9102 9103; do for i in $(seq 1 60); do timeout 3 bash -c "</dev/tcp/$IP/$p" 2>/dev/null && break; sleep 5; done; done
WH="http://webhook4.mcp-pilot.svc.cluster.local:8000/hook"
META='"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"axis2","version":"0.1"},"io.modelcontextprotocol/clientCapabilities":{}}'

echo "# 축 2 결과: 대안 대비 (자동 생성)" > "$F"
note ""
note "실행 $(date '+%Y-%m-%d %H:%M'). 파드 하나에 컨테이너 셋, 공유 \`work.py\`, IP \`$IP\`."
note "A2A는 a2a-sdk 1.1.2, MCP는 mcp 2.0.0, HTTP는 표준 라이브러리. 작업 시간 15초."
note "게이트웨이는 거치지 않는다."
note ""

# ── 호출 도구 ──
# 각 호출의 상태, 소요 시간, 보낸 바이트, 받은 바이트를 한 줄로 기록한다.
call() { # call <tag> <url> <body> [헤더...]
  local tag="$1" url="$2" body="$3"; shift 3
  curl -s --max-time 90 -o "$OUT/$tag.res" \
    -w "%{http_code} %{time_total} %{size_upload} %{size_download}" \
    -X POST "$url" -H 'Content-Type: application/json' "$@" -d "$body"; }
callg() { # callg <tag> <url>  (GET)
  curl -s --max-time 60 -o "$OUT/$1.res" -w "%{http_code} %{time_total} %{size_upload} %{size_download}" "$2"; }
res() { head -c "${2:-160}" "$OUT/$1.res" | tr '\n' ' '; }
# MCP 응답은 SSE로 올 수 있어 본문에서 JSON만 뽑는다.
mcpjson() { python3 -c "
import re,sys,json
t=open('$OUT/$1.res').read()
m=re.search(r'\{.*\}', t, re.S)
print(json.dumps(json.loads(m.group(0)), ensure_ascii=False)[:400] if m else t[:200])"; }
mcptext() { python3 -c "
import re,json
t=open('$OUT/$1.res').read(); m=re.search(r'\{.*\}', t, re.S)
d=json.loads(m.group(0)) if m else {}
c=(d.get('result') or {}).get('content') or []
print(''.join(x.get('text','') for x in c) or json.dumps(d.get('error') or d)[:160])"; }
jres() { python3 -c "
import json
try: d=json.load(open('$OUT/$1.res'))
except Exception: print('파싱 실패'); raise SystemExit
$2"; }

# ══════════ 시나리오 1: 짧은 작업 ══════════
log "시나리오 1: 짧은 작업 (${REPS}회)"
note "## 시나리오 1. 짧은 작업 (1초 안)"; note ""
note "같은 입력 \`fast:hello-world\`를 세 구현에 ${REPS}회씩 보낸다. A2A는 카드를 처음 한 번 조회한다."
note ""
note '```'
printf "%-6s %-8s %10s %10s %10s %10s\n" "구현" "왕복" "지연중앙" "요청바이트" "응답바이트" "결과일치" >> "$F"
for arm in http mcp a2a; do
  times=(); ups=(); downs=(); ok=1; rt=1; result=""
  for n in $(seq 1 $REPS); do
    case $arm in
      http)
        r=$(call "s1-http-$n" "http://$IP:9103/" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"do-work\",\"params\":{\"text\":\"fast:hello-world\"}}")
        result=$(jres "s1-http-$n" "print(d.get('result',{}).get('text'))") ;;
      mcp)
        r=$(call "s1-mcp-$n" "http://$IP:9102/mcp" \
          "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"do-work\",\"arguments\":{\"text\":\"fast:hello-world\"},$META}}" \
          -H 'Accept: application/json, text/event-stream' -H 'MCP-Protocol-Version: 2026-07-28' \
          -H 'Mcp-Method: tools/call' -H 'Mcp-Name: do-work')
        result=$(mcptext "s1-mcp-$n") ;;
      a2a)
        if [ "$n" = "1" ]; then
          rc=$(callg "s1-a2a-card" "http://$IP:9101/.well-known/agent-card.json")
          note "(A2A 카드 조회 1회: HTTP $(echo $rc | cut -d' ' -f1), 응답 $(echo $rc | cut -d' ' -f4) 바이트)"
          rt=2
        fi
        r=$(call "s1-a2a-$n" "http://$IP:9101/a2a/jsonrpc" \
          "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"message/send\",\"params\":{\"message\":{\"role\":\"user\",\"messageId\":\"m$n\",\"parts\":[{\"kind\":\"text\",\"text\":\"fast:hello-world\"}]}}}")
        result=$(jres "s1-a2a-$n" "
r=d.get('result',{}); a=(r.get('artifacts') or [{}])[0]
print(''.join(p.get('text','') for p in a.get('parts',[])))") ;;
    esac
    times+=($(echo $r | cut -d' ' -f2)); ups+=($(echo $r | cut -d' ' -f3)); downs+=($(echo $r | cut -d' ' -f4))
    [ "$result" = "processed:fast:hello-world:16" ] || ok=0
  done
  med=$(printf '%s\n' "${times[@]}" | sort -n | awk '{a[NR]=$1} END{print a[int((NR+1)/2)]}')
  printf "%-6s %-8s %10s %10s %10s %10s\n" "$arm" "${rt}회" \
    "$(python3 -c "print(f'{float('$med')*1000:.1f}ms')")" "${ups[0]}" "${downs[0]}" \
    "$( [ $ok = 1 ] && echo 일치 || echo 불일치 )" >> "$F"
done
note '```'
note ""
note "왕복은 첫 호출 기준이다(A2A는 카드 조회가 앞에 붙는다). 이후 호출은 셋 다 1회다."
note ""

log "시나리오 1: 실패 표면"
note "### 실패 표면 (백엔드를 내린 직후 첫 호출)"; note ""
kubectl --context $CTX -n $NS scale deploy/axis2-arms --replicas=0 >/dev/null 2>&1
sleep 12
r=$(call f-http "http://$IP:9103/" '{"jsonrpc":"2.0","id":1,"method":"do-work","params":{"text":"x"}}')
note "- HTTP: 코드 $(echo $r | cut -d' ' -f1), $(res f-http 100)"
r=$(call f-mcp "http://$IP:9102/mcp" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"do-work\",\"arguments\":{\"text\":\"x\"},$META}}" \
  -H 'Accept: application/json, text/event-stream' -H 'MCP-Protocol-Version: 2026-07-28' -H 'Mcp-Method: tools/call' -H 'Mcp-Name: do-work')
note "- MCP: 코드 $(echo $r | cut -d' ' -f1), $(res f-mcp 100)"
r=$(call f-a2a "http://$IP:9101/a2a/jsonrpc" '{"jsonrpc":"2.0","id":1,"method":"message/send","params":{"message":{"role":"user","messageId":"f1","parts":[{"kind":"text","text":"x"}]}}}')
note "- A2A: 코드 $(echo $r | cut -d' ' -f1), $(res f-a2a 100)"
r=$(callg f-card "http://$IP:9101/.well-known/agent-card.json")
note "- A2A 카드 조회: 코드 $(echo $r | cut -d' ' -f1)"
note ""
note "코드 000은 연결 자체가 안 된 것이다. 세 구현 모두 같은 파드에 있어 실패 조건이 같다."
kubectl --context $CTX -n $NS scale deploy/axis2-arms --replicas=1 >/dev/null 2>&1
kubectl --context $CTX -n $NS rollout status deploy/axis2-arms --timeout=600s >/dev/null 2>&1
for p in 9101 9102 9103; do for i in $(seq 1 60); do timeout 3 bash -c "</dev/tcp/$IP/$p" 2>/dev/null && break; sleep 5; done; done
note ""

# ══════════ 시나리오 2: 오래 걸리는 작업 ══════════
log "시나리오 2: HTTP 앱 핸들"
note "## 시나리오 2. 오래 걸리는 작업 (15초)"; note ""
note "### HTTP 구현: 앱 수준 핸들 (이 서버가 정한 규약)"; note ""
t0=$(python3 -c "import time;print(time.time())")
r=$(call s2-http-start "http://$IP:9103/" '{"jsonrpc":"2.0","id":1,"method":"work-start","params":{"text":"hello-world"}}')
el() { python3 -c "import time;print(f'{time.time()-$t0:.1f}s')"; }
JOB=$(jres s2-http-start "print(d['result']['jobId'])")
note "- \`work-start\`: 코드 $(echo $r | cut -d' ' -f1), 첫 응답 $(el), jobId=\`$JOB\`, 응답 $(echo $r | cut -d' ' -f4) 바이트"
polls=0; pbytes=0
while :; do
  r=$(call s2-http-poll "http://$IP:9103/" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"work-status\",\"params\":{\"jobId\":\"$JOB\"}}")
  polls=$((polls+1)); pbytes=$(echo $r | cut -d' ' -f4)
  s=$(jres s2-http-poll "print(d['result']['state'])")
  [ "$s" = "done" ] && break
  [ $polls -gt 40 ] && break
  sleep 1
done
note "- 폴링 ${polls}회(1초 간격) 뒤 완료. 최종 응답 $(el), 상태 확인 1회당 $pbytes 바이트"
note "- 결과: $(jres s2-http-poll "print(d['result']['text'])")"
r=$(call s2-http-c1 "http://$IP:9103/" '{"jsonrpc":"2.0","id":1,"method":"work-start","params":{"text":"cancel-me"}}')
J2=$(jres s2-http-c1 "print(d['result']['jobId'])"); sleep 2
r=$(call s2-http-c2 "http://$IP:9103/" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"work-cancel\",\"params\":{\"jobId\":\"$J2\"}}")
note "- 진행 중 취소: $(res s2-http-c2 120) (표시만 바꾸고 작업 스레드는 계속 돈다)"
note ""

log "시나리오 2: MCP 두 경로"
note "### MCP 구현: 코어에 태스크가 없어 두 경로를 다 잰다"; note ""
note "\`mcp==2.0.0\` 코어에는 태스크 수명주기가 없다. \`resultType\`만 필수이고 \`tasks/*\`는"
note "확장이 서브하는 메서드로만 언급된다. 그래서 (a) 차단 호출과 (b) 앱 수준 핸들 둘뿐이다."
note ""
t0=$(python3 -c "import time;print(time.time())")
r=$(call s2-mcp-block "http://$IP:9102/mcp" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"do-work-slow\",\"arguments\":{\"text\":\"hello-world\"},$META}}" \
  -H 'Accept: application/json, text/event-stream' -H 'MCP-Protocol-Version: 2026-07-28' -H 'Mcp-Method: tools/call' -H 'Mcp-Name: do-work-slow')
note "- (a) 차단 호출 \`do-work-slow\`: 코드 $(echo $r | cut -d' ' -f1), 첫 응답이 곧 최종 응답 $(el), 응답 $(echo $r | cut -d' ' -f4) 바이트"
note "  결과: $(mcptext s2-mcp-block)"
t0=$(python3 -c "import time;print(time.time())")
r=$(call s2-mcp-start "http://$IP:9102/mcp" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"work-start\",\"arguments\":{\"text\":\"hello-world\"},$META}}" \
  -H 'Accept: application/json, text/event-stream' -H 'MCP-Protocol-Version: 2026-07-28' -H 'Mcp-Method: tools/call' -H 'Mcp-Name: work-start')
MJOB=$(mcptext s2-mcp-start)
note "- (b) \`work-start\`: 코드 $(echo $r | cut -d' ' -f1), 첫 응답 $(el), jobId=\`$MJOB\`, 응답 $(echo $r | cut -d' ' -f4) 바이트"
polls=0; pbytes=0
while :; do
  r=$(call s2-mcp-poll "http://$IP:9102/mcp" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"work-status\",\"arguments\":{\"job_id\":\"$MJOB\"},$META}}" \
    -H 'Accept: application/json, text/event-stream' -H 'MCP-Protocol-Version: 2026-07-28' -H 'Mcp-Method: tools/call' -H 'Mcp-Name: work-status')
  polls=$((polls+1)); pbytes=$(echo $r | cut -d' ' -f4)
  s=$(mcptext s2-mcp-poll)
  case "$s" in done:*) break;; esac
  [ $polls -gt 40 ] && break
  sleep 1
done
note "- 폴링 ${polls}회 뒤 상태: \`$(mcptext s2-mcp-poll)\`. 최종 $(el), 상태 확인 1회당 $pbytes 바이트"
note ""

log "시나리오 2: A2A 세 경로"
note "### A2A 구현: 프로토콜이 진행 확인을 정의한다 (폴링, 스트리밍, 푸시)"; note ""
t0=$(python3 -c "import time;print(time.time())")
r=$(call s2-a2a-send "http://$IP:9101/a2a/jsonrpc" '{"jsonrpc":"2.0","id":1,"method":"message/send","params":{"message":{"role":"user","messageId":"L1","parts":[{"kind":"text","text":"hello-world"}]},"configuration":{"blocking":false}}}')
AT=$(jres s2-a2a-send "print(d['result']['id'])")
note "- (a) 비차단 \`message/send\`: 코드 $(echo $r | cut -d' ' -f1), 첫 응답 $(el), taskId=\`$AT\`, 응답 $(echo $r | cut -d' ' -f4) 바이트, 상태=$(jres s2-a2a-send "print(d['result']['status']['state'])")"
polls=0; pbytes=0
while :; do
  r=$(call s2-a2a-poll "http://$IP:9101/a2a/jsonrpc" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tasks/get\",\"params\":{\"id\":\"$AT\"}}")
  polls=$((polls+1)); pbytes=$(echo $r | cut -d' ' -f4)
  s=$(jres s2-a2a-poll "print(d['result']['status']['state'])")
  [ "$s" = "completed" ] && break
  [ $polls -gt 40 ] && break
  sleep 1
done
note "- 폴링 ${polls}회 뒤 completed. 최종 $(el), 상태 확인 1회당 $pbytes 바이트(태스크 객체 전체가 실린다)"
t0=$(python3 -c "import time;print(time.time())")
curl -s --max-time 60 -N -X POST "http://$IP:9101/a2a/jsonrpc" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"message/stream","params":{"message":{"role":"user","messageId":"L2","parts":[{"kind":"text","text":"hello-world"}]}}}' > "$OUT/s2-a2a-stream.txt" 2>&1
note "- (b) 스트리밍 \`message/stream\`: 이벤트 $(grep -c '^data:' "$OUT/s2-a2a-stream.txt")개, 완료까지 $(el), 총 $(wc -c < "$OUT/s2-a2a-stream.txt") 바이트"
note "  첫 이벤트 종류: $(grep -m1 '^data:' "$OUT/s2-a2a-stream.txt" | sed 's/^data: //' | python3 -c "
import json,sys
try:
    r=json.load(sys.stdin).get('result',{}); print(r.get('kind'), '/', (r.get('status') or {}).get('state'))
except Exception: print('파싱 실패')")"
t0=$(python3 -c "import time;print(time.time())")
r=$(call s2-a2a-p1 "http://$IP:9101/a2a/jsonrpc" '{"jsonrpc":"2.0","id":1,"method":"message/send","params":{"message":{"role":"user","messageId":"L3","parts":[{"kind":"text","text":"hello-world"}]},"configuration":{"blocking":false}}}')
PT=$(jres s2-a2a-p1 "print(d['result']['id'])")
r=$(call s2-a2a-p2 "http://$IP:9101/a2a/jsonrpc" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tasks/pushNotificationConfig/set\",\"params\":{\"taskId\":\"$PT\",\"pushNotificationConfig\":{\"url\":\"$WH\",\"id\":\"ax2\",\"token\":\"axis2\"}}}")
note "- (c) 푸시 설정: 코드 $(echo $r | cut -d' ' -f1). 왕복 2회로 등록하고 이후 폴링이 0회다"
sleep 20
note "  수신기 로그(최근 2줄):"; note '```'
kubectl --context $CTX -n $NS logs deploy/webhook4 --tail=2 >> "$F" 2>&1
note '```'
r=$(call s2-a2a-c1 "http://$IP:9101/a2a/jsonrpc" '{"jsonrpc":"2.0","id":1,"method":"message/send","params":{"message":{"role":"user","messageId":"L4","parts":[{"kind":"text","text":"hello-world"}]},"configuration":{"blocking":false}}}')
CT=$(jres s2-a2a-c1 "print(d['result']['id'])"); sleep 2
r=$(call s2-a2a-c2 "http://$IP:9101/a2a/jsonrpc" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tasks/cancel\",\"params\":{\"id\":\"$CT\"}}")
note "- 진행 중 취소: 코드 $(echo $r | cut -d' ' -f1), 상태=$(jres s2-a2a-c2 "print(d['result']['status']['state'])") (프로토콜이 정의한 규약)"
note ""

log "시나리오 2: 재시작 뒤 상태 생존"
note "### 백엔드 재시작 뒤 상태가 남는가"; note ""
r=$(call sv-http "http://$IP:9103/" '{"jsonrpc":"2.0","id":1,"method":"work-start","params":{"text":"survive"}}')
SJ=$(jres sv-http "print(d['result']['jobId'])")
r=$(call sv-a2a "http://$IP:9101/a2a/jsonrpc" '{"jsonrpc":"2.0","id":1,"method":"message/send","params":{"message":{"role":"user","messageId":"S1","parts":[{"kind":"text","text":"survive"}]},"configuration":{"blocking":false}}}')
SA=$(jres sv-a2a "print(d['result']['id'])")
kubectl --context $CTX -n $NS rollout restart deploy/axis2-arms >/dev/null 2>&1
kubectl --context $CTX -n $NS rollout status deploy/axis2-arms --timeout=600s >/dev/null 2>&1
for p in 9101 9103; do for i in $(seq 1 60); do timeout 3 bash -c "</dev/tcp/$IP/$p" 2>/dev/null && break; sleep 5; done; done
sleep 5
r=$(call sv-http2 "http://$IP:9103/" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"work-status\",\"params\":{\"jobId\":\"$SJ\"}}")
note "- HTTP 앱 핸들 조회: $(res sv-http2 140)"
r=$(call sv-a2a2 "http://$IP:9101/a2a/jsonrpc" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tasks/get\",\"params\":{\"id\":\"$SA\"}}")
note "- A2A \`tasks/get\`: $(res sv-a2a2 140)"
note ""
note "둘 다 파드 메모리에 있어 사라진다. 다른 점은 오류의 모양뿐이다."
note ""

# ── 클라이언트가 알아야 하는 것 ──
note "### 클라이언트 코드가 상대마다 달라지는 지점"; note ""
note "진행 확인과 취소를 만들 때 클라이언트가 상대 서버에 맞춰 알아야 하는 것이다."
note "A2A 열은 스펙이 정한 것이라 상대가 바뀌어도 같다. 나머지 둘은 서버가 정한 것이라 상대마다 다시 만든다."
note ""
note "| 알아야 하는 것 | HTTP | MCP | A2A |"
note "|---|---|---|---|"
note "| 시작 호출 이름 | \`work-start\`(이 서버가 정함) | 도구 \`work-start\`(이 서버가 정함) | \`message/send\`(스펙) |"
note "| 식별자 이름 | \`jobId\`(이 서버가 정함) | 도구 인자 \`job_id\`(이 서버가 정함) | \`taskId\`(스펙) |"
note "| 상태 확인 이름 | \`work-status\`(이 서버가 정함) | 도구 \`work-status\`(이 서버가 정함) | \`tasks/get\`(스펙) |"
note "| 상태 값 | \`pending/running/done\`(이 서버가 정함) | 같은 값을 문자열로(이 서버가 정함) | \`submitted/working/completed\` 등(스펙) |"
note "| 취소 규약 | \`work-cancel\`(이 서버가 정함, 표시만) | 도구 \`work-cancel\`(이 서버가 정함, 표시만) | \`tasks/cancel\`(스펙, 실제로 멈춤) |"
note "| 밀어 주는 알림 | 없음(직접 만든다) | 없음(직접 만든다) | \`pushNotificationConfig/set\`(스펙) |"
note "| 진행 중 스트리밍 | 없음(직접 만든다) | 없음(직접 만든다) | \`message/stream\`(스펙) |"
note ""
note "상대가 바뀌면 다시 만들어야 하는 항목 수: HTTP 5, MCP 5, A2A 0."
note ""

note "## 서버 로그(구현별 마지막 5줄)"
for c in a2a mcp http; do
  note "### $c"; note '```'
  kubectl --context $CTX -n $NS logs deploy/axis2-arms -c $c --tail=5 >> "$F" 2>&1
  note '```'
done
log "=== 축 2 완료: $F ==="
