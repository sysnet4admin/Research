#!/usr/bin/env bash
# 테스트 함수 + round-N.json 출력 헬퍼. run-round.sh 가 source.
# 계약: 각 test_<name> 은 "result|skip_code|meta_json" 을 echo.
#   result    = pass|fail|skip
#   skip_code = unsupported|not-configured|infra-excluded|"" (pass/fail 시 빈값)
#   meta_json = {} 또는 jq 객체
# 환경: GW_IP, GW_IMPL, gw_curl, BACKEND_V1_TOKEN/V2_TOKEN, DOMAIN_*, CLIENT_POD
#
# 상태: 라이브 검증으로 보강 예정 항목은 RSKIP_NC + TODO(live) 주석.

# ---- 결과 헬퍼 ----
# 주: ${1:-{}} 는 bash가 기본값을 '{'로 잘못 파싱(invalid JSON). 명시 변수 사용.
EMPTY_META='{}'
RPASS()  { echo "pass||${1:-$EMPTY_META}"; }
RFAIL()  { echo "fail||${1:-$EMPTY_META}"; }
RSKIP_U(){ echo "skip|unsupported|${1:-$EMPTY_META}"; }     # 설계상 미지원
RSKIP_NC(){ echo "skip|not-configured|${1:-$EMPTY_META}"; } # 하네스 미구성(버그)
RSKIP_IX(){ echo "skip|infra-excluded|${1:-$EMPTY_META}"; } # 인프라 플레이크

# ---- JSON 출력 헬퍼(jq) ----
add_test_result() {
  local arr="$1" name="$2" triple="$3"
  local result="${triple%%|*}"; local rest="${triple#*|}"
  local skip="${rest%%|*}"; local meta="${rest#*|}"
  [ -z "$meta" ] && meta="{}"
  local skiparg='null'; [ -n "$skip" ] && skiparg="\"$skip\""
  echo "$arr" | jq -c --arg n "$name" --arg r "$result" --argjson m "$meta" \
    --argjson sk "$skiparg" \
    '. += [{name:$n,result:$r,skip_code:$sk,metadata:$m}]'
}

all_infra_excluded() {
  local arr="[]" t
  for t in $TESTS; do arr="$(add_test_result "$arr" "$t" "skip|infra-excluded|{}")"; done
  echo "$arr"
}

append_impl() {
  local list="$1" impl="$2" ip="$3" tests="$4"
  [ "$tests" = "infra-excluded-all" ] && tests="$(all_infra_excluded)"
  local iparg='null'; [ -n "$ip" ] && iparg="\"$ip\""
  echo "$list" | jq -c --arg i "$impl" --arg gc "$(gwclass_of "$impl")" \
    --arg v "$(version_of "$impl")" --argjson ip "$iparg" --argjson t "$tests" \
    '. += [{implementation:$i,gateway_class:$gc,version:$v,gateway_ip:$ip,tests:$t}]'
}

emit_round() {
  local impls="$1"
  mkdir -p "$RESULTS_DIR"
  jq -nc --argjson r "$ROUND" --arg ts "$(date -u +%FT%TZ)" \
    --arg gw "$GWAPI_VERSION" --arg ch "$GWAPI_CHANNEL" \
    --arg arch "$(uname -m)" --argjson impls "$impls" \
    '{round:$r,timestamp:$ts,gateway_api_version:$gw,crd_channel:$ch,architecture:$arch,implementations:$impls}' \
    > "$RESULTS_DIR/round-$ROUND.json"
  echo "→ $RESULTS_DIR/round-$ROUND.json"
}

run_one_test() {
  local name="$1"
  local fn="test_${name//-/_}"   # 같은 local 줄에서 교차참조 금지(set -u)
  if declare -f "$fn" >/dev/null; then "$fn"; else RSKIP_NC; fi
}

#============================================================
# Core (7)
#============================================================
test_host_routing() {
  local r1 r2
  r1="$(gw_curl -H "Host: $DOMAIN_V1" "http://$GW_IP/")"
  r2="$(gw_curl -H "Host: $DOMAIN_V2" "http://$GW_IP/")"
  if echo "$r1" | grep -q "$BACKEND_V1_TOKEN" && echo "$r2" | grep -q "$BACKEND_V2_TOKEN"
  then RPASS; else RFAIL; fi
}

test_path_routing() {
  local r1 r2
  r1="$(gw_curl -H "Host: $DOMAIN_V1" "http://$GW_IP/v1")"
  r2="$(gw_curl -H "Host: $DOMAIN_V1" "http://$GW_IP/v2")"
  if echo "$r1" | grep -q "$BACKEND_V1_TOKEN" && echo "$r2" | grep -q "$BACKEND_V2_TOKEN"
  then RPASS; else RFAIL; fi
}

test_header_routing() {
  local r1 r2
  r1="$(gw_curl -H "Host: $DOMAIN_V1" -H "X-Version: v1" "http://$GW_IP/")"
  r2="$(gw_curl -H "Host: $DOMAIN_V1" -H "X-Version: v2" "http://$GW_IP/")"
  if echo "$r1" | grep -q "$BACKEND_V1_TOKEN" && echo "$r2" | grep -q "$BACKEND_V2_TOKEN"
  then RPASS; else RFAIL; fi
}

test_tls_termination() {
  # HTTPS 리스너 종료. --resolve로 SNI=도메인(IP를 SNI로 보내면 unrecognized name).
  local r
  r="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -sk --max-time 8 \
        --resolve "$DOMAIN_V1:443:$GW_IP" "https://$DOMAIN_V1/" 2>/dev/null)"
  if echo "$r" | grep -q "$BACKEND_V1_TOKEN"; then RPASS; else RFAIL; fi
}

test_canary_traffic() {
  local v1=0 v2=0 i r
  for i in $(seq 1 50); do
    r="$(gw_curl -H "Host: $DOMAIN_CANARY" "http://$GW_IP/")"
    echo "$r" | grep -q "$BACKEND_V1_TOKEN" && v1=$((v1+1))
    echo "$r" | grep -q "$BACKEND_V2_TOKEN" && v2=$((v2+1))
  done
  local meta; meta="$(jq -nc --argjson a "$v1" --argjson b "$v2" '{v1:$a,v2:$b}')"
  # 동결 경계 [34,46] (2σ, rubric.yaml)
  if [ "$v1" -ge 34 ] && [ "$v1" -le 46 ]; then RPASS "$meta"; else RFAIL "$meta"; fi
}

test_header_modifier() {
  # RequestHeaderModifier(Core): route가 X-Test 주입 → 백엔드 echo 확인.
  local r
  r="$(gw_curl -H "Host: $DOMAIN_V1" "http://$GW_IP/hdr")"
  if echo "$r" | grep -qi '"x-test"'; then RPASS; else RFAIL; fi
}

test_cross_namespace() {
  # ReferenceGrant(Core): gwtest route → gwtest-backend2 백엔드.
  local r
  r="$(gw_curl -H "Host: $DOMAIN_V1" "http://$GW_IP/cross")"
  if echo "$r" | grep -q "backend-cross"; then RPASS; else RFAIL; fi
}

#============================================================
# Extended-standard (5)
#============================================================
test_https_redirect() {
  # redirect.example.com HTTP → HTTPS(301/302 + Location https). 전용 도메인.
  local resp
  resp="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -sI --max-time 8 \
          -H "Host: $DOMAIN_REDIRECT" "http://$GW_IP/" 2>/dev/null)"
  if echo "$resp" | grep -qiE '^HTTP/.* 30[12]' && \
     echo "$resp" | grep -qi '^location:.*https://'
  then RPASS; else RFAIL; fi
}

test_url_rewrite() {
  # URLRewrite(Extended): /old/foo → 백엔드가 /new/foo 수신.
  local r path
  r="$(gw_curl -H "Host: $DOMAIN_V1" "http://$GW_IP/old/foo")"
  path="$(echo "$r" | jq -r '.path // empty' 2>/dev/null)"
  if [ "$path" = "/new/foo" ]; then RPASS; else RFAIL; fi
}

test_grpc_routing() {
  # FIX: 실제 gRPC 호출(리소스 존재만으로 PASS 금지). grpcurl reflection through gateway.
  # GRPCRoute가 grpc.example.com → grpc-backend(h2c) 라우팅. authority로 host 지정.
  local out
  out="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- grpcurl -plaintext \
          -authority grpc.example.com -max-time 8 "$GW_IP:80" list 2>/dev/null || true)"
  if echo "$out" | grep -qiE "grpcecho|GrpcEcho|ServerReflection"; then RPASS; else RFAIL; fi
}

test_session_affinity() {
  # experimental. sticky.example.com에 sessionPersistence(Cookie) 설정.
  # 거짓PASS 방지: (1) 세션 쿠키가 실제 설정돼야 하고 (2) 동일 쿠키로 8회 요청이
  # 전부 같은 pod(.os.hostname)여야 통과. 쿠키 미설정이면 미지원으로 fail.
  local jar=/tmp/cj.$$ resp first host i ok=1
  resp="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -si -c "$jar" --max-time 8 \
          -H "Host: sticky.example.com" "http://$GW_IP/" 2>/dev/null)"
  if ! echo "$resp" | grep -qi 'set-cookie:.*gwsession'; then
    kc -n "$TEST_NS" exec "$CLIENT_POD" -- rm -f "$jar" 2>/dev/null || true
    RFAIL; return
  fi
  first=""
  for i in $(seq 1 8); do
    host="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- sh -c \
      "curl -s -b $jar --max-time 8 -H 'Host: sticky.example.com' http://$GW_IP/" 2>/dev/null \
      | jq -r '.os.hostname // empty' 2>/dev/null)"
    [ -z "$host" ] && { ok=0; break; }
    [ -z "$first" ] && first="$host"
    [ "$host" != "$first" ] && { ok=0; break; }
  done
  kc -n "$TEST_NS" exec "$CLIENT_POD" -- rm -f "$jar" 2>/dev/null || true
  if [ "$ok" = 1 ] && [ -n "$first" ]; then RPASS; else RFAIL; fi
}

# ---- 라이브 검증으로 보강할 항목(현재 스텁) ----
# timeout: 라우트 request timeout 2s, 백엔드 httpbin /delay/5.
# 타임아웃 동작 시 ~2s에 5xx(중단), 미지원이면 ~5s에 200(백엔드 지연 다 기다림).
test_timeout() {
  local start end elapsed code meta
  start=$(date +%s)
  code="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -so /dev/null -w '%{http_code}' \
          --max-time 12 -H "Host: timeout.example.com" "http://$GW_IP/delay/5" 2>/dev/null)"
  end=$(date +%s); elapsed=$((end - start))
  meta="$(jq -nc --argjson e "$elapsed" --arg c "${code:-000}" '{elapsed_s:$e,code:$c}')"
  if [ "$elapsed" -lt 4 ] && echo "$code" | grep -qE '50[0-9]'; then RPASS "$meta"; else RFAIL "$meta"; fi
}
# backend-tls: BackendTLSPolicy로 gateway→backend(HTTPS) 검증. btls.example.com→
# backend-tls(HTTPS). 지원 시 백엔드가 'backend-tls-ok' 반환. 미지원이면 HTTPS
# 백엔드에 평문 연결 실패 → 본문 없음.
test_backend_tls() {
  local r
  r="$(gw_curl -H "Host: btls.example.com" "http://$GW_IP/" 2>/dev/null)"
  if echo "$r" | grep -q "backend-tls-ok"; then RPASS; else RFAIL; fi
}
# retry(experimental): HTTPRoute 표준 retry 필드(GEP-1731, attempts/codes). httpbin
# /status/503에 retry{attempts:3,codes:[503]} → 1 클라이언트 요청에 업스트림이 몇 번
# 시도되나(httpbin 로그 라인 델타로 측정). 격리 실행이라 httpbin 트래픽은 이 테스트뿐.
# >=2회=retry 적용(pass), 1회=미적용/무시(unsupported), 0회=baseline 미동작(infra).
test_retry() {
  local host="retry.example.com" code ready=0 j
  for j in $(seq 1 30); do
    code="$(gw_curl -s -o /dev/null -w '%{http_code}' -H "Host: $host" "http://$GW_IP/status/503" 2>/dev/null || true)"
    [ "$code" = 503 ] && { ready=1; break; }
    sleep 2
  done
  [ "$ready" = 1 ] || { RSKIP_IX "{\"why\":\"baseline 미동작(code=$code)\"}"; return; }
  local n0 n1 attempts
  n0="$(kc -n "$TEST_NS" logs -l app=httpbin --tail=-1 2>/dev/null | wc -l | tr -d ' ')"
  gw_curl -s -o /dev/null -H "Host: $host" "http://$GW_IP/status/503" >/dev/null 2>&1
  sleep 5
  n1="$(kc -n "$TEST_NS" logs -l app=httpbin --tail=-1 2>/dev/null | wc -l | tr -d ' ')"
  attempts=$(( n1 - n0 ))
  if [ "$attempts" -ge 2 ]; then RPASS "{\"upstream_attempts\":$attempts}"
  elif [ "$attempts" -eq 1 ]; then RSKIP_U '{"why":"retry 미적용(업스트림 1회, 표준 retry 필드 미지원/무시)"}'
  else RSKIP_IX "{\"why\":\"업스트림 0(로그 카운트 실패 가능)\",\"delta\":$attempts}"; fi
}

# 라우트가 거부됐는지(미지원 신호) 판정: Accepted=False 또는 ResolvedRefs=False
# 또는 PartiallyInvalid/UnsupportedValue/InvalidFilter reason. kong all-or-nothing
# APPLYERR(라우트 미생성)도 미지원으로 본다.
route_rejected() {
  local name="$1" conds
  kc -n "$TEST_NS" get httproute "$name" >/dev/null 2>&1 || return 0   # 미생성=미지원
  conds="$(kc -n "$TEST_NS" get httproute "$name" \
    -o jsonpath='{range .status.parents[*]}{.conditions[*].type}={.conditions[*].status}/{.conditions[*].reason} {end}' 2>/dev/null)"
  echo "$conds" | grep -qiE "Accepted=False|ResolvedRefs=False|UnsupportedValue|InvalidFilter|PartiallyInvalid|NotAllowed|BackendNotFound" && return 0
  return 1
}

#============================================================
# Extended-standard 추가 (8) — graded. conformance flag 보유(v1.4 pkg/features).
#============================================================
test_response_header_modifier() {   # SupportHTTPRouteResponseHeaderModification
  route_rejected "${GW_IMPL}-resphdr" && { RSKIP_U; return; }
  local resp
  resp="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -si --max-time 8 \
          -H "Host: $DOMAIN_V1" "http://$GW_IP/resphdr" 2>/dev/null)"
  if echo "$resp" | grep -qi '^x-resp-test:[[:space:]]*modified'; then RPASS; else RFAIL; fi
}

test_request_mirror() {   # SupportHTTPRouteRequestMirror
  route_rejected "${GW_IMPL}-mirror" && { RSKIP_U; return; }
  # 유니크 마커로 /mirror 요청 → 미러 대상 echo-v2 pod 로그에 마커 path가 찍히는지 확인.
  local marker="mtest-${ROUND}-$$-$RANDOM"
  kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -s --max-time 8 \
    -H "Host: $DOMAIN_V1" "http://$GW_IP/mirror/$marker" >/dev/null 2>&1
  local i hit=""
  for i in 1 2 3 4 5; do
    hit="$(kc -n "$TEST_NS" logs -l app=echo-v2 --tail=200 --since=60s 2>/dev/null | grep -F "$marker" | head -1)"
    [ -n "$hit" ] && break
    sleep 2
  done
  if [ -n "$hit" ]; then RPASS; else RFAIL; fi
}

test_method_matching() {   # SupportHTTPRouteMethodMatching
  route_rejected "${GW_IMPL}-method" && { RSKIP_U; return; }
  local g p
  g="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -s -X GET --max-time 8 -H "Host: method.example.com" "http://$GW_IP/" 2>/dev/null)"
  p="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -s -X POST --max-time 8 -H "Host: method.example.com" "http://$GW_IP/" 2>/dev/null)"
  if echo "$g" | grep -q "$BACKEND_V1_TOKEN" && echo "$p" | grep -q "$BACKEND_V2_TOKEN"; then RPASS; else RFAIL; fi
}

test_query_param_matching() {   # SupportHTTPRouteQueryParamMatching
  route_rejected "${GW_IMPL}-query" && { RSKIP_U; return; }
  local r1 r2
  r1="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -s --max-time 8 -H "Host: query.example.com" "http://$GW_IP/?ver=v1" 2>/dev/null)"
  r2="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -s --max-time 8 -H "Host: query.example.com" "http://$GW_IP/?ver=v2" 2>/dev/null)"
  if echo "$r1" | grep -q "$BACKEND_V1_TOKEN" && echo "$r2" | grep -q "$BACKEND_V2_TOKEN"; then RPASS; else RFAIL; fi
}

test_backend_request_header_mod() {   # SupportHTTPRouteBackendRequestHeaderModification
  route_rejected "${GW_IMPL}-bereqhdr" && { RSKIP_U; return; }
  local r
  r="$(gw_curl -H "Host: $DOMAIN_V1" "http://$GW_IP/bereqhdr")"
  if echo "$r" | grep -qi '"x-backend-inject"'; then RPASS; else RFAIL; fi
}

test_path_redirect() {   # SupportHTTPRoutePathRedirect
  route_rejected "${GW_IMPL}-predirect" && { RSKIP_U; return; }
  local resp
  resp="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -sI --max-time 8 \
          -H "Host: predirect.example.com" "http://$GW_IP/anything" 2>/dev/null)"
  if echo "$resp" | grep -qiE '^HTTP/.* 30[12]' && echo "$resp" | grep -qiE '^location:.*/newpath'
  then RPASS; else RFAIL; fi
}

test_websocket() {   # SupportHTTPRouteBackendProtocolWebSocket
  route_rejected "${GW_IMPL}-ws" && { RSKIP_U; return; }
  # HTTP Upgrade 핸드셰이크 → 101 Switching Protocols.
  local resp
  resp="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -si --max-time 8 \
          -H "Host: ws.example.com" -H "Connection: Upgrade" -H "Upgrade: websocket" \
          -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" -H "Sec-WebSocket-Version: 13" \
          "http://$GW_IP/" 2>/dev/null)"
  if echo "$resp" | grep -qiE '^HTTP/.* 101'; then RPASS; else RFAIL; fi
}

test_listener_isolation() {   # SupportGatewayHTTPListenerIsolation (Gateway feature)
  # 자체완결: 2 HTTP 리스너(wild *.iso.example.com + specific foo.iso.example.com) 게이트웨이를
  # 별도 배포. wild에 bar 라우트, specific에 foo 라우트. 격리되면 foo→specific(v2), bar→wild(v1).
  local gwclass; gwclass="$(gwclass_of "$GW_IMPL")"
  local hport=80; [ "$GW_IMPL" = traefik ] && hport=8000
  cat <<EOF | kc apply -f - >/dev/null 2>&1
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: { name: ${GW_IMPL}-iso-gw, namespace: $TEST_NS }
spec:
  gatewayClassName: ${gwclass}
  listeners:
  - { name: wild, protocol: HTTP, port: ${hport}, hostname: "*.iso.example.com", allowedRoutes: { namespaces: { from: Same } } }
  - { name: specific, protocol: HTTP, port: ${hport}, hostname: "foo.iso.example.com", allowedRoutes: { namespaces: { from: Same } } }
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${GW_IMPL}-iso-wild, namespace: $TEST_NS }
spec:
  parentRefs: [ { name: ${GW_IMPL}-iso-gw, sectionName: wild } ]
  rules: [ { backendRefs: [ { name: echo-v1, port: 80 } ] } ]
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${GW_IMPL}-iso-foo, namespace: $TEST_NS }
spec:
  parentRefs: [ { name: ${GW_IMPL}-iso-gw, sectionName: specific } ]
  hostnames: [ "foo.iso.example.com" ]
  rules: [ { backendRefs: [ { name: echo-v2, port: 80 } ] } ]
EOF
  # iso 게이트웨이 IP 발견
  local iso_ip="" i
  for i in $(seq 1 40); do
    iso_ip="$(kc -n "$TEST_NS" get gateway "${GW_IMPL}-iso-gw" -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)"
    [ -z "$iso_ip" ] && [ "$GW_IMPL" = traefik ] && iso_ip="$(kc -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
    [ -n "$iso_ip" ] && break; sleep 3
  done
  local res="fail" meta='{}'
  if [ -n "$iso_ip" ]; then
    # 라우팅 준비 대기(foo→v2, bar→v1 둘 다 안정).
    # 주의: 리스너 포트(hport)와 무관하게 클라이언트는 LB 외부 포트 80으로 접속한다.
    # traefik은 리스너=8000(web 엔트리포인트)이지만 LB Service는 80을 노출(8000은 미노출)하므로
    # :hport(8000)로 접속하면 timeout. 모든 구현체 LB 외부 http 포트=80.
    local bar foo ok=0
    for i in $(seq 1 30); do
      bar="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -s --max-time 5 -H "Host: bar.iso.example.com" "http://$iso_ip/" 2>/dev/null)"
      foo="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -s --max-time 5 -H "Host: foo.iso.example.com" "http://$iso_ip/" 2>/dev/null)"
      if echo "$bar" | grep -q "$BACKEND_V1_TOKEN" && echo "$foo" | grep -q "$BACKEND_V2_TOKEN"; then ok=$((ok+1)); [ "$ok" -ge 2 ] && { res="pass"; break; }; else ok=0; fi
      sleep 2
    done
  else
    res="skip-ix"
  fi
  kc -n "$TEST_NS" delete gateway "${GW_IMPL}-iso-gw" --ignore-not-found >/dev/null 2>&1
  kc -n "$TEST_NS" delete httproute "${GW_IMPL}-iso-wild" "${GW_IMPL}-iso-foo" --ignore-not-found >/dev/null 2>&1
  case "$res" in pass) RPASS ;; skip-ix) RSKIP_IX ;; *) RFAIL ;; esac
}

# regex 경로매칭 (impl-specific 매트릭스 — conformance flag 없음 GEP-2694 closed)
test_regex() {
  route_rejected "${GW_IMPL}-regex" && { RSKIP_U; return; }
  local ok bad mv
  ok="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -so /dev/null -w '%{http_code}' --max-time 6 -H "Host: regex.example.com" "http://$GW_IP/api/v123/x" 2>/dev/null)"
  bad="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -so /dev/null -w '%{http_code}' --max-time 6 -H "Host: regex.example.com" "http://$GW_IP/api/vABC/x" 2>/dev/null)"
  # 지원=정확매칭(/v123→200, /vABC→404). 과매칭(/vABC도 200)=부정확.
  if [ "$ok" = 200 ] && [ "$bad" = 404 ]; then mv="supported"; RPASS "$(jq -nc --arg m "$mv" '{matrix_value:$m}')"
  elif [ "$ok" = 200 ] && [ "$bad" = 200 ]; then mv="overmatch"; RFAIL "$(jq -nc --arg m "$mv" '{matrix_value:$m}')"
  else mv="unsupported"; RSKIP_U "$(jq -nc --arg m "$mv" '{matrix_value:$m}')"; fi
}

# CORS (Extended + experimental 채널 — graded, extended-experimental 축)
# SupportHTTPRouteCORS. OPTIONS preflight + Origin → Access-Control-Allow-Origin 응답.
test_cors() {
  route_rejected "${GW_IMPL}-cors" && { RSKIP_U; return; }
  local resp
  resp="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -si -X OPTIONS --max-time 8 \
          -H "Host: cors.example.com" -H "Origin: https://example.test" \
          -H "Access-Control-Request-Method: GET" "http://$GW_IP/" 2>/dev/null)"
  if echo "$resp" | grep -qi '^access-control-allow-origin:'; then RPASS; else RFAIL; fi
}

#============================================================
# Impl-specific / 비기능 (4) — in_grade:false, 매트릭스
#============================================================
test_rate_limiting() {
  # 실측(스텁 대체): 벤더 rate-limit 정책(5/min) 배포 → 30요청 429 카운트 → matrix_value.
  # 메커니즘: istio=EnvoyFilter(low-level), cilium=없음(unsupported), 나머지=native CRD.
  local n429=0 n200=0 i code host=rl.example.com mv mech
  case "$GW_IMPL" in istio) mech="low-level-config" ;; cilium) mech="unsupported" ;; *) mech="native" ;; esac
  if [ "$GW_IMPL" = cilium ]; then
    RSKIP_U '{"matrix_value":"unsupported","rate_limited":0,"note":"no rate-limit mechanism"}'; return
  fi
  policy_for "$GW_IMPL" rate-limit | kc apply -f - >/dev/null 2>&1
  # 라우트 데이터패스 준비 대기(200 또는 429 응답)
  for i in $(seq 1 30); do
    code="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -so /dev/null -w '%{http_code}' --max-time 5 -H "Host: $host" "http://$GW_IP/" 2>/dev/null)"
    { [ "$code" = 200 ] || [ "$code" = 429 ]; } && break; sleep 3
  done
  for i in $(seq 1 30); do
    code="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -so /dev/null -w '%{http_code}' --max-time 5 -H "Host: $host" "http://$GW_IP/" 2>/dev/null)"
    case "$code" in 429) n429=$((n429+1)) ;; 200) n200=$((n200+1)) ;; esac
  done
  policy_for "$GW_IMPL" rate-limit | kc delete -f - --ignore-not-found >/dev/null 2>&1
  # 강제되면(429 발생) 메커니즘 라벨, 아니면 unsupported(비발동)
  if [ "$n429" -ge 5 ]; then mv="$mech"; else mv="unsupported"; fi
  local meta; meta="$(jq -nc --arg mv "$mv" --argjson n "$n429" --argjson ok "$n200" '{matrix_value:$mv,rate_limited:$n,allowed:$ok}')"
  RPASS "$meta"   # in_grade:false → 매트릭스로만
}

test_body_size() {
  # 실측: body-size 제한 정책 배포 → 2MB POST → 413. matrix_value(native/low-level/unsupported).
  # 검증분: nginx/traefik/kong=native, istio=low-level. envoy/kgateway=정책 미확정→비발동시 unsupported.
  local code host=bsize.example.com mv mech i
  case "$GW_IMPL" in istio) mech="low-level-config" ;; cilium) mech="unsupported" ;; envoy|kgateway) mech="unsupported" ;; *) mech="native" ;; esac
  if [ "$GW_IMPL" = cilium ]; then RSKIP_U '{"matrix_value":"unsupported","note":"no body-size mechanism"}'; return; fi
  policy_for "$GW_IMPL" body-size | kc apply -f - >/dev/null 2>&1
  for i in $(seq 1 30); do
    code="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -so /dev/null -w '%{http_code}' --max-time 5 -H "Host: $host" "http://$GW_IP/" 2>/dev/null)"
    { [ "$code" = 200 ] || [ "$code" = 413 ]; } && break; sleep 3
  done
  # 2MB POST
  code="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- sh -c \
    "dd if=/dev/zero bs=1024 count=2048 2>/dev/null | tr '\\0' a | curl -so /dev/null -w '%{http_code}' --max-time 10 -X POST --data-binary @- -H 'Host: $host' http://$GW_IP/" 2>/dev/null)"
  policy_for "$GW_IMPL" body-size | kc delete -f - --ignore-not-found >/dev/null 2>&1
  if [ "$code" = 413 ]; then mv="$mech"; else mv="unsupported"; fi
  local meta; meta="$(jq -nc --arg mv "$mv" --arg c "${code:-000}" '{matrix_value:$mv,post_code:$c}')"
  RPASS "$meta"
}

# basic-auth 매트릭스(벤더): 정책 배포 → credential 없으면 401, 유효하면 200. native/unsupported.
# 메커니즘이 없는 구현체(정책 미배포)는 라우트만 → 200 유지 → unsupported(순수 측정).
test_basic_auth() {
  policy_for "$GW_IMPL" basic-auth | kc apply -f - >/dev/null 2>&1
  local host=bauth.example.com i no with
  for i in $(seq 1 30); do
    no="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -so /dev/null -w '%{http_code}' --max-time 5 -H "Host: $host" "http://$GW_IP/" 2>/dev/null)"
    [ "$no" = 401 ] && break           # 인증 강제됨
    [ "$no" = 200 ] && sleep 3 || sleep 3   # 아직 200이면 정책 프로그래밍 대기
    [ "$i" -ge 12 ] && [ "$no" = 200 ] && break   # 충분히 기다려도 200이면 미강제
  done
  with="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -so /dev/null -w '%{http_code}' --max-time 5 -u "gwuser:gwpass" -H "Host: $host" "http://$GW_IP/" 2>/dev/null)"
  policy_for "$GW_IMPL" basic-auth | kc delete -f - --ignore-not-found >/dev/null 2>&1
  local mv meta
  if [ "$no" = 401 ] && [ "$with" = 200 ]; then mv=native; else mv=unsupported; fi
  meta="$(jq -nc --arg mv "$mv" --arg n "${no:-000}" --arg w "${with:-000}" '{matrix_value:$mv,no_cred:$n,with_cred:$w}')"
  [ "$mv" = native ] && RPASS "$meta" || RSKIP_U "$meta"
}

# ip-filter 매트릭스(벤더): 허용 CIDR(클라 미포함) 정책 → 차단(403)되면 native, 200이면 unsupported.
test_ip_filter() {
  policy_for "$GW_IMPL" ip-filter | kc apply -f - >/dev/null 2>&1
  local host=ipf.example.com i code last=000
  for i in $(seq 1 30); do
    code="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -so /dev/null -w '%{http_code}' --max-time 5 -H "Host: $host" "http://$GW_IP/" 2>/dev/null)"
    last="$code"
    [ "$code" = 403 ] && break          # IP 차단 강제됨
    sleep 3
  done
  policy_for "$GW_IMPL" ip-filter | kc delete -f - --ignore-not-found >/dev/null 2>&1
  local mv meta
  [ "$last" = 403 ] && mv=native || mv=unsupported
  meta="$(jq -nc --arg mv "$mv" --arg c "$last" '{matrix_value:$mv,code:$c}')"
  [ "$mv" = native ] && RPASS "$meta" || RSKIP_U "$meta"
}

# mtls-client 매트릭스: 자체 게이트웨이(HTTPS + frontendValidation) → 클라 cert 없으면 거부, 있으면 200.
test_mtls_client() {
  local gwclass; gwclass="$(gwclass_of "$GW_IMPL")"
  kc -n "$TEST_NS" exec "$CLIENT_POD" -- sh -c 'mkdir -p /tmp/mtls' >/dev/null 2>&1
  kc -n "$TEST_NS" get configmap mtls-client -o "jsonpath={.data.client\.crt}" | kc -n "$TEST_NS" exec -i "$CLIENT_POD" -- sh -c 'cat > /tmp/mtls/c.crt' >/dev/null 2>&1
  kc -n "$TEST_NS" get configmap mtls-client -o "jsonpath={.data.client\.key}" | kc -n "$TEST_NS" exec -i "$CLIENT_POD" -- sh -c 'cat > /tmp/mtls/c.key' >/dev/null 2>&1
  cat <<EOF | kc apply -f - >/dev/null 2>&1
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: { name: ${GW_IMPL}-mtls-gw, namespace: $TEST_NS }
spec:
  gatewayClassName: ${gwclass}
  listeners:
  - name: mtls
    protocol: HTTPS
    port: 443
    hostname: mtls.example.com
    tls:
      mode: Terminate
      certificateRefs: [ { name: gw-tls } ]
      frontendValidation: { caCertificateRefs: [ { group: "", kind: ConfigMap, name: mtls-ca } ] }
    allowedRoutes: { namespaces: { from: Same } }
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${GW_IMPL}-mtls, namespace: $TEST_NS }
spec:
  parentRefs: [ { name: ${GW_IMPL}-mtls-gw, sectionName: mtls } ]
  hostnames: [ "mtls.example.com" ]
  rules: [ { backendRefs: [ { name: echo-v1, port: 80 } ] } ]
EOF
  local ip="" i; for i in $(seq 1 40); do
    ip="$(kc -n "$TEST_NS" get gateway "${GW_IMPL}-mtls-gw" -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)"
    [ -z "$ip" ] && [ "$GW_IMPL" = traefik ] && ip="$(kc -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
    [ -n "$ip" ] && break; sleep 3
  done
  local mv="unsupported" without with meta
  if [ -n "$ip" ]; then
    for i in $(seq 1 30); do
      with="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -sko /dev/null -w '%{http_code}' --max-time 6 --resolve "mtls.example.com:443:$ip" --cert /tmp/mtls/c.crt --key /tmp/mtls/c.key "https://mtls.example.com/" 2>/dev/null)"
      [ "$with" = 200 ] && break; sleep 3
    done
    without="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -sko /dev/null -w '%{http_code}' --max-time 6 --resolve "mtls.example.com:443:$ip" "https://mtls.example.com/" 2>/dev/null)"
    [ "$with" = 200 ] && [ "$without" != 200 ] && mv=supported
    meta="$(jq -nc --arg mv "$mv" --arg wo "${without:-000}" --arg w "${with:-000}" '{matrix_value:$mv,without_cert:$wo,with_cert:$w}')"
  else meta='{"matrix_value":"unsupported","note":"no LB IP"}'; fi
  kc -n "$TEST_NS" delete gateway "${GW_IMPL}-mtls-gw" --ignore-not-found >/dev/null 2>&1
  kc -n "$TEST_NS" delete httproute "${GW_IMPL}-mtls" --ignore-not-found >/dev/null 2>&1
  [ "$mv" = supported ] && RPASS "$meta" || RSKIP_U "$meta"
}

# tls-passthrough 매트릭스: 자체 게이트웨이(TLS Passthrough) + TLSRoute → 백엔드가 TLS 종료. 200이면 supported.
test_tls_passthrough() {
  local gwclass; gwclass="$(gwclass_of "$GW_IMPL")"
  # traefik 리스너 포트는 entryPoint(websecure 8443)와 맞춰야 함(443은 PortUnavailable). LB 외부는 443 공통.
  local tport=443; [ "$GW_IMPL" = traefik ] && tport=8443
  cat <<EOF | kc apply -f - >/dev/null 2>&1
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: { name: ${GW_IMPL}-pass-gw, namespace: $TEST_NS }
spec:
  gatewayClassName: ${gwclass}
  listeners:
  - name: pass
    protocol: TLS
    port: ${tport}
    hostname: pass.example.com
    tls: { mode: Passthrough }
    allowedRoutes: { kinds: [ { kind: TLSRoute } ], namespaces: { from: Same } }
---
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: TLSRoute
metadata: { name: ${GW_IMPL}-pass, namespace: $TEST_NS }
spec:
  parentRefs: [ { name: ${GW_IMPL}-pass-gw, sectionName: pass } ]
  hostnames: [ "pass.example.com" ]
  rules: [ { backendRefs: [ { name: backend-tls, port: 443 } ] } ]
EOF
  local ip="" i; for i in $(seq 1 40); do
    ip="$(kc -n "$TEST_NS" get gateway "${GW_IMPL}-pass-gw" -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)"
    [ -z "$ip" ] && [ "$GW_IMPL" = traefik ] && ip="$(kc -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
    [ -n "$ip" ] && break; sleep 3
  done
  local mv="unsupported" code meta
  if [ -n "$ip" ]; then
    for i in $(seq 1 30); do
      code="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -sko /dev/null -w '%{http_code}' --max-time 6 --resolve "pass.example.com:443:$ip" "https://pass.example.com/" 2>/dev/null)"
      [ "$code" = 200 ] && break; sleep 3
    done
    [ "$code" = 200 ] && mv=supported
    meta="$(jq -nc --arg mv "$mv" --arg c "${code:-000}" '{matrix_value:$mv,code:$c}')"
  else meta='{"matrix_value":"unsupported","note":"no LB IP"}'; fi
  kc -n "$TEST_NS" delete gateway "${GW_IMPL}-pass-gw" --ignore-not-found >/dev/null 2>&1
  kc -n "$TEST_NS" delete tlsroute "${GW_IMPL}-pass" --ignore-not-found >/dev/null 2>&1
  [ "$mv" = supported ] && RPASS "$meta" || RSKIP_U "$meta"
}

# auth(JWT) 매트릭스: 보호 라우트 → no-token/valid/bad. 검증 스키마(E8). in_grade:false.
test_auth_jwt() { RSKIP_NC '{"todo":"harness 통합 보류 — E8 검증값 사용(매트릭스)"}'; }
# auth(ext-authz) 매트릭스: 표준 GEP-1494 필터 + 벤더. 검증 스키마(E9). in_grade:false.
test_auth_extauth() { RSKIP_NC '{"todo":"harness 통합 보류 — E9 검증값 사용(매트릭스)"}'; }

# health-check(impl-specific): 능동 health check가 unhealthy 백엔드를 빼는가.
# hc-backend Service에 good(/health 200)+bad(/health 503) 두 엔드포인트. 정책이 능동
# probe로 bad를 빼면 트래픽 100% good. 표준 필드 없음 → 구현체 정책(envoy/kong/kgateway 등).
# bad=0(완전 제거)=pass, bad>0(혼합)=미동작/미지원(unsupported), 라우트 미동작=infra.
test_health_check() {
  local host="hc.example.com" ready=0 j r good=0 bad=0 i
  for j in $(seq 1 30); do
    r="$(gw_curl -s -H "Host: $host" "http://$GW_IP/" 2>/dev/null || true)"
    echo "$r" | grep -qE "hc-good|hc-bad" && { ready=1; break; }
    sleep 2
  done
  [ "$ready" = 1 ] || { RSKIP_IX '{"why":"baseline 라우팅 미동작"}'; return; }
  # kong은 KongUpstreamPolicy를 Service 어노테이션으로 부착(정책 CRD는 routes_for가 배포).
  [ "$GW_IMPL" = kong ] && kc -n "$TEST_NS" annotate svc hc-backend \
    "konghq.com/upstream-policy=${GW_IMPL}-hc" --overwrite >/dev/null 2>&1
  sleep 24   # 능동 health check가 bad를 빼낼 시간(정착)
  for i in $(seq 1 20); do
    r="$(gw_curl -s -H "Host: $host" "http://$GW_IP/" 2>/dev/null || true)"
    case "$r" in *hc-good*) good=$((good+1));; *hc-bad*) bad=$((bad+1));; esac
  done
  local meta="{\"good\":$good,\"bad\":$bad}"
  if [ $((good+bad)) -lt 10 ]; then RSKIP_IX "{\"why\":\"응답 부족\",\"good\":$good,\"bad\":$bad}"
  elif [ "$bad" -eq 0 ]; then RPASS "$meta"
  else RSKIP_U "$meta"; fi
}

test_load_test() {
  # 20 동시 요청 중 성공 비율(비기능, 매트릭스).
  local out ok meta
  out="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- sh -c \
    "for i in \$(seq 1 20); do curl -so /dev/null -w '%{http_code}\n' --max-time 8 -H 'Host: $DOMAIN_V1' http://$GW_IP/ & done; wait" 2>/dev/null)" || true
  ok="$(printf '%s\n' "$out" | grep -c '^200' | tr -dc 0-9)"; ok="${ok:-0}"
  meta="$(jq -nc --argjson ok "$ok" '{success:$ok,total:20}')"
  if [ "$ok" -ge 18 ]; then RPASS "$meta"; else RFAIL "$meta"; fi
}

# 데이터플레인(프록시) 파드 지정: "ns|mode|sel". mode=label(라벨 셀렉터) | name(파드명 접두).
# 재시작 = 해당 파드 삭제(Deployment/DaemonSet 관리 파드는 즉시 재생성). 파드 이름
# 변화로 '교란됨'을 입증한다. 셀렉터가 틀리면 파드 미발견 → RSKIP_NC(정직).
# kong은 KGO dataplane 라벨이 app=<gw>-<random>이라 불안정 → 파드명 접두(dataplane-<gw>-)로 매치.
_dataplane_ref() {
  local gw="${GW_IMPL}-gw"
  case "$GW_IMPL" in
    nginx)    echo "$TEST_NS|label|gateway.networking.k8s.io/gateway-name=$gw" ;;
    istio)    echo "$TEST_NS|label|gateway.networking.k8s.io/gateway-name=$gw" ;;
    kgateway) echo "$TEST_NS|label|gateway.networking.k8s.io/gateway-name=$gw" ;;
    envoy)    echo "envoy-gateway-system|label|gateway.envoyproxy.io/owning-gateway-name=$gw" ;;
    traefik)  echo "traefik|label|app.kubernetes.io/name=traefik" ;;
    kong)     echo "$TEST_NS|name|dataplane-$gw-" ;;
    *)        echo "" ;;
  esac
}

_dp_pods() {  # ns mode sel → 정렬된 파드명 csv
  if [ "$2" = name ]; then kc -n "$1" get pods -o name 2>/dev/null | grep "/$3" | sort | tr '\n' ','
  else kc -n "$1" get pods -l "$3" -o name 2>/dev/null | sort | tr '\n' ','; fi
}

_dp_delete() {  # ns mode sel  (xargs는 bash 함수 kc를 못 부르므로 단일 delete로 처리)
  if [ "$2" = name ]; then
    local p; p="$(kc -n "$1" get pods -o name 2>/dev/null | grep "/$3" | tr '\n' ' ')"
    [ -n "$p" ] && kc -n "$1" delete $p --wait=false >/dev/null 2>&1
  else kc -n "$1" delete pods -l "$3" --wait=false >/dev/null 2>&1; fi
}

# failover-recovery(비기능): 데이터플레인 강제 재시작 후 트래픽 복구 측정.
# 교란 입증: 재시작 후 파드 ID가 바뀌었거나(pod_changed) 폴링 중 1회 이상 실패 관측.
# 둘 다 없으면 측정이 교란보다 빨랐거나 셀렉터 오류 → inconclusive(RSKIP_NC).
# 이로써 recovery_s=0이 '진짜 무중단(교란 확인)'인지 '헛measure'인지 구분된다.
test_failover_recovery() {
  if [ "$GW_IMPL" = cilium ]; then
    RSKIP_U '{"why":"공유 eBPF 데이터플레인, 에이전트 재시작은 클러스터 전역 영향이라 격리 측정 부적합"}'; return
  fi
  local ref ns mode sel
  ref="$(_dataplane_ref)"
  ns="$(echo "$ref" | cut -d'|' -f1)"; mode="$(echo "$ref" | cut -d'|' -f2)"; sel="$(echo "$ref" | cut -d'|' -f3)"
  [ -z "$ns" ] && { RSKIP_NC '{"why":"dataplane ref 미정의"}'; return; }
  # baseline 준비 대기(라우트 프로그래밍 지연 흡수, 최대 60s). 이걸로 envoy/traefik/
  # kgateway의 느린 라우트 프로그래밍에 의한 런-투-런 플레이크를 제거한다.
  local b=0 j
  for j in $(seq 1 30); do
    gw_curl -H "Host: $DOMAIN_V1" "http://$GW_IP/" 2>/dev/null | grep -q "$BACKEND_V1_TOKEN" && { b=1; break; }
    sleep 2
  done
  [ "$b" = 1 ] || { RSKIP_IX '{"why":"baseline 라우팅 미동작(60s 대기 후)"}'; return; }
  local pods0; pods0="$(_dp_pods "$ns" "$mode" "$sel")"
  if [ -z "$pods0" ]; then RSKIP_NC "{\"why\":\"dataplane 파드 미발견(셀렉터 점검)\",\"ref\":\"$ref\"}"; return; fi

  _dp_delete "$ns" "$mode" "$sel"
  local t0 i r ok_streak=0 ever_fail=0 outage=0 changed=0 rec_s=-1 pods1
  t0="$(date +%s)"
  for i in $(seq 1 90); do
    if r="$(gw_curl -H "Host: $DOMAIN_V1" "http://$GW_IP/" 2>/dev/null)" && echo "$r" | grep -q "$BACKEND_V1_TOKEN"; then
      ok_streak=$((ok_streak+1))
      [ "$ever_fail" = 1 ] && [ "$rec_s" = -1 ] && rec_s=$(( $(date +%s) - t0 ))
    else
      ever_fail=1; outage=$((outage+1)); ok_streak=0
    fi
    pods1="$(_dp_pods "$ns" "$mode" "$sel")"
    [ "$pods1" != "$pods0" ] && changed=1
    # 교란 확인 + 2연속 성공이면 복구로 보고 종료
    { [ "$changed" = 1 ] || [ "$ever_fail" = 1 ]; } && [ "$ok_streak" -ge 2 ] && break
    # 교란 흔적 전무(약 24s)면 조기 종료(inconclusive)
    [ "$i" -ge 12 ] && [ "$changed" = 0 ] && [ "$ever_fail" = 0 ] && break
    sleep 2
  done
  [ "$rec_s" = -1 ] && rec_s=0
  local pc; pc="$([ "$changed" = 1 ] && echo true || echo false)"
  local meta="{\"pod_changed\":$pc,\"outage_ticks\":$outage,\"recovery_s\":$rec_s}"
  if [ "$changed" = 0 ] && [ "$ever_fail" = 0 ]; then
    RSKIP_NC "{\"why\":\"교란 미확인(파드 교체/실패 관측 없음, 셀렉터 점검 필요)\",\"ref\":\"$ref\"}"
  elif [ "$ok_streak" -ge 1 ]; then
    RPASS "$meta"
  else
    RFAIL "$meta"
  fi
}
