#!/usr/bin/env bash
# 측정 1라운드 → round-N.json (gwlib.py 스키마).
# 전제: install 단계로 7개 GatewayClass 준비됨. 픽스처(백엔드/Gateway/route)는
# 여기서 배포하고 끝나면 정리한다.
#
# 사용: ROUND=1 ./run-round.sh
#
# 상태: 프레임워크. 개별 테스트 단언은 lib-tests.sh 에서 라이브 검증으로 완성.

set -uo pipefail   # -e 미사용: 개별 테스트 실패 허용
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/config.sh"
source "$HERE/lib-tests.sh"

MANIFESTS="$HERE/manifests"
CLIENT_POD="gw-client"

# rubric 항목(순서 = 리포트 순서). lib-tests.sh 에 test_<name> 함수.
# Core(7) + Extended-standard(13) + capability(retry/session-affinity/cors) + 매트릭스/비기능.
# TESTS는 env로 오버라이드 가능(포커스 측정: TESTS="ip-filter basic-auth" ...).
TESTS="${TESTS:-host-routing path-routing header-routing tls-termination canary-traffic \
header-modifier cross-namespace \
https-redirect url-rewrite timeout backend-tls grpc-routing \
response-header-modifier request-mirror method-matching query-param-matching \
backend-request-header-mod path-redirect websocket listener-isolation \
retry session-affinity cors \
regex rate-limiting body-size auth-jwt auth-extauth \
ip-filter basic-auth tls-passthrough \
health-check load-test failover-recovery}"

#=== 픽스처 ===
ensure_certs() {
  # gw-tls: 게이트웨이 HTTPS 리스너용 자체서명(*.example.com)
  if ! kc -n "$TEST_NS" get secret gw-tls >/dev/null 2>&1; then
    local d; d="$(mktemp -d)"
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$d/k" -out "$d/c" -days 365 \
      -subj "/CN=*.example.com" -addext "subjectAltName=DNS:*.example.com,DNS:example.com" 2>/dev/null
    kc -n "$TEST_NS" create secret tls gw-tls --cert="$d/c" --key="$d/k"
    rm -rf "$d"
  fi
  # backend-tls: CA + 서버 cert(CN/SAN backend-tls.local). BackendTLSPolicy 검증용
  if ! kc -n "$TEST_NS" get secret backend-tls-cert >/dev/null 2>&1; then
    local d; d="$(mktemp -d)"
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$d/ca.key" -out "$d/ca.crt" \
      -days 365 -subj "/CN=gwtest-ca" 2>/dev/null
    openssl req -newkey rsa:2048 -nodes -keyout "$d/s.key" -out "$d/s.csr" \
      -subj "/CN=backend-tls.local" 2>/dev/null
    openssl x509 -req -in "$d/s.csr" -CA "$d/ca.crt" -CAkey "$d/ca.key" -CAcreateserial \
      -days 365 -extfile <(printf 'subjectAltName=DNS:backend-tls.local') -out "$d/s.crt" 2>/dev/null
    kc -n "$TEST_NS" create secret tls backend-tls-cert --cert="$d/s.crt" --key="$d/s.key"
    kc -n "$TEST_NS" create configmap backend-ca --from-file=ca.crt="$d/ca.crt"
    rm -rf "$d"
  fi
  # mTLS 클라이언트: 클라 CA(게이트웨이 frontendValidation용 configmap) + 클라 cert/key(테스트가 pod로 주입).
  if ! kc -n "$TEST_NS" get configmap mtls-ca >/dev/null 2>&1; then
    local d; d="$(mktemp -d)"
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$d/ca.key" -out "$d/ca.crt" \
      -days 365 -subj "/CN=gwtest-client-ca" 2>/dev/null
    openssl req -newkey rsa:2048 -nodes -keyout "$d/cl.key" -out "$d/cl.csr" \
      -subj "/CN=gwtest-client" 2>/dev/null
    openssl x509 -req -in "$d/cl.csr" -CA "$d/ca.crt" -CAkey "$d/ca.key" -CAcreateserial \
      -days 365 -out "$d/cl.crt" 2>/dev/null
    kc -n "$TEST_NS" create configmap mtls-ca --from-file=ca.crt="$d/ca.crt"
    kc -n "$TEST_NS" create configmap mtls-client \
      --from-file=client.crt="$d/cl.crt" --from-file=client.key="$d/cl.key"
    rm -rf "$d"
  fi
}

# auth(JWT) 자료 생성: RSA 키 + JWKS + 서명된 RS256 토큰. 매트릭스 auth-jwt 측정용.
#  - configmap jwt-cm: jwks.json / token.jwt / pub.pem (테스트가 kc 로 읽어 사용)
#  - secret jwks-secret (type nginx.org/jwk): NGF File source용
# 토큰: iss=https://poc.gateway.test, aud=gw-poc, exp +10y. 멱등(이미 있으면 skip).
JWT_ISS="https://poc.gateway.test"
JWT_AUD="gw-poc"
ensure_jwt() {
  kc -n "$TEST_NS" get configmap jwt-cm >/dev/null 2>&1 && return 0
  local d; d="$(mktemp -d)"
  openssl genrsa -out "$d/priv.pem" 2048 2>/dev/null
  openssl rsa -in "$d/priv.pem" -pubout -out "$d/pub.pem" 2>/dev/null
  local kid="poc-key-1" exp; exp=$(( $(date +%s) + 315360000 ))
  b64u() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
  local h p si sig
  h="$(printf '{"alg":"RS256","typ":"JWT","kid":"%s"}' "$kid" | b64u)"
  p="$(printf '{"iss":"%s","aud":"%s","sub":"tester","exp":%d,"iat":%d}' \
        "$JWT_ISS" "$JWT_AUD" "$exp" "$(date +%s)" | b64u)"
  si="${h}.${p}"
  sig="$(printf '%s' "$si" | openssl dgst -sha256 -sign "$d/priv.pem" -binary | b64u)"
  printf '%s.%s' "$si" "$sig" > "$d/token.jwt"
  python3 - "$kid" "$d/pub.pem" >"$d/jwks.json" <<'PY'
import sys, subprocess, base64, json
kid, pub = sys.argv[1], sys.argv[2]
mod_hex = subprocess.check_output(["openssl","rsa","-pubin","-in",pub,"-noout","-modulus"]).decode().strip().split("=")[1]
b64=lambda b: base64.urlsafe_b64encode(b).decode().rstrip("=")
print(json.dumps({"keys":[{"kty":"RSA","use":"sig","alg":"RS256","kid":kid,
      "n":b64(bytes.fromhex(mod_hex)),"e":b64((65537).to_bytes(3,"big"))}]}))
PY
  kc -n "$TEST_NS" create configmap jwt-cm \
    --from-file=jwks.json="$d/jwks.json" \
    --from-file=token.jwt="$d/token.jwt" \
    --from-file=pub.pem="$d/pub.pem" >/dev/null
  kc -n "$TEST_NS" create secret generic jwks-secret \
    --type=nginx.org/jwk --from-file=jwk="$d/jwks.json" >/dev/null
  rm -rf "$d"
}

# basic-auth 자료: htpasswd(gwuser/gwpass) 멀티키 시크릿 + kong consumer/credential.
#  - ba-htpasswd: .htpasswd(envoy SecurityPolicy) / users(traefik Middleware) / htpasswd(NGF AuthenticationFilter)
#  - kong: KongConsumer + basic-auth credential secret
BA_USER="gwuser"; BA_PASS="gwpass"
ensure_authz() {
  # basic-auth는 구현체마다 시크릿 형식/타입/키가 전부 다르다(라이브 검증으로 확정):
  #  envoy   : Opaque, 키 .htpasswd, SHA1({SHA}) 형식만(apr1 거부→500)
  #  traefik : Opaque, 단일키 users, apr1 (멀티키 시크릿 거부 "must be single element")
  #  nginx   : type nginx.org/htpasswd, 키 auth, apr1 (Opaque/basic-auth 타입 거부)
  #  kong    : KongConsumer + basic-auth credential(KGO 2.1은 시크릿 못 읽어 검증 실패=정직 기록)
  local sha apr
  sha="${BA_USER}:{SHA}$(printf '%s' "$BA_PASS" | openssl sha1 -binary | openssl base64)"
  apr="${BA_USER}:$(openssl passwd -apr1 "$BA_PASS" 2>/dev/null)"
  kc -n "$TEST_NS" get secret ba-envoy >/dev/null 2>&1 || \
    kc -n "$TEST_NS" create secret generic ba-envoy --from-literal=.htpasswd="$sha" >/dev/null 2>&1 || true
  kc -n "$TEST_NS" get secret ba-traefik >/dev/null 2>&1 || \
    kc -n "$TEST_NS" create secret generic ba-traefik --from-literal=users="$apr" >/dev/null 2>&1 || true
  if ! kc -n "$TEST_NS" get secret ba-nginx >/dev/null 2>&1; then
    cat <<EOF | kc apply -f - >/dev/null 2>&1 || true
apiVersion: v1
kind: Secret
metadata: { name: ba-nginx, namespace: ${TEST_NS} }
type: nginx.org/htpasswd
stringData: { auth: "${apr}" }
EOF
  fi
  if ! kc -n "$TEST_NS" get kongconsumer ba-consumer >/dev/null 2>&1; then
    cat <<EOF | kc apply -f - >/dev/null 2>&1 || true
apiVersion: v1
kind: Secret
metadata: { name: ba-kong-cred, namespace: ${TEST_NS}, labels: { konghq.com/credential: basic-auth } }
type: Opaque
stringData: { username: ${BA_USER}, password: ${BA_PASS} }
---
apiVersion: configuration.konghq.com/v1
kind: KongConsumer
metadata: { name: ba-consumer, namespace: ${TEST_NS}, annotations: { kubernetes.io/ingress.class: kong } }
username: ${BA_USER}
credentials: [ ba-kong-cred ]
EOF
  fi
}

deploy_fixtures() {
  echo "==> 네임스페이스 + 인증서"
  # 레이스 방지(자기정리): 기존 네임스페이스를 삭제하고 완전히 사라진 뒤 새로 생성.
  # (terminating 중 생성하면 'namespace is being terminated'로 백엔드 생성 실패)
  local i ns
  for ns in "$TEST_NS" "$BACKEND2_NS"; do
    kc delete ns "$ns" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    for i in $(seq 1 75); do
      kc get ns "$ns" >/dev/null 2>&1 || break
      [ "$i" = 1 ] && echo "  ($ns 정리 대기...)"
      sleep 4
    done
  done
  kc create namespace "$TEST_NS" --dry-run=client -o yaml | kc apply -f - >/dev/null
  kc create namespace "$BACKEND2_NS" --dry-run=client -o yaml | kc apply -f - >/dev/null
  ensure_certs
  ensure_jwt
  ensure_authz
  echo "==> 백엔드 배포(echo, grpc, httpbin, backend-tls, ws, ext-authz)"
  kc apply -f "$MANIFESTS/00-backends.yaml"
  kc apply -f "$MANIFESTS/backend-tls.yaml"
  kc apply -f "$MANIFESTS/01-extras.yaml"
  kc apply -f "$MANIFESTS/hc-backends.yaml"
  kc -n "$TEST_NS" rollout status deploy/echo-v1 --timeout=120s
  kc -n "$TEST_NS" rollout status deploy/echo-v2 --timeout=120s
  kc -n "$TEST_NS" rollout status deploy/backend-tls --timeout=120s
  kc -n "$TEST_NS" rollout status deploy/ws-backend --timeout=120s
  kc -n "$TEST_NS" rollout status deploy/extauthz --timeout=120s
  kc -n "$TEST_NS" rollout status deploy/hc-good --timeout=120s
  kc -n "$TEST_NS" rollout status deploy/hc-bad --timeout=120s
  echo "==> 클라이언트(netshoot: curl/openssl/grpcurl)"
  kc -n "$TEST_NS" run "$CLIENT_POD" --image=nicolaka/netshoot --restart=Never \
    --command -- sleep 36000 >/dev/null 2>&1 || true
  kc -n "$TEST_NS" wait --for=condition=Ready "pod/$CLIENT_POD" --timeout=120s
}

teardown_fixtures() {
  echo "==> 픽스처 정리"
  kc delete -f "$MANIFESTS/01-extras.yaml" --ignore-not-found >/dev/null 2>&1 || true
  kc delete -f "$MANIFESTS/backend-tls.yaml" --ignore-not-found >/dev/null 2>&1 || true
  kc delete -f "$MANIFESTS/00-backends.yaml" --ignore-not-found >/dev/null 2>&1 || true
  for impl in $IMPLS; do
    kc -n "$TEST_NS" delete gateway "${impl}-gw" --ignore-not-found >/dev/null 2>&1 || true
  done
}

# Gateway만 배포(라우트 제외). Traefik은 entryPoint 8000/8443.
deploy_gateway() {
  local impl="$1" gwclass; gwclass="$(gwclass_of "$impl")"
  local hport=80 hsport=443
  if [ "$impl" = traefik ]; then hport=8000; hsport=8443; fi
  IMPL="$impl" GWCLASS="$gwclass" NS="$TEST_NS" HTTP_PORT="$hport" HTTPS_PORT="$hsport" \
    envsubst '$IMPL $GWCLASS $NS $HTTP_PORT $HTTPS_PORT' \
    < "$MANIFESTS/gateway.tmpl.yaml" | kc apply -f - >/dev/null
}

# 테스트별 라우트 YAML(단일 소스). impl/test로 해당 라우트만 출력 → apply/delete.
# Kong은 all-or-nothing config라 테스트별 격리 배포에 사용. 나머지는 배치.
routes_for() {
  local impl="$1" test="$2" gw="${1}-gw"
  case "$test" in
    host-routing|tls-termination|load-test|failover-recovery)
      cat <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${impl}-host-v1, namespace: ${TEST_NS} }
spec:
  parentRefs: [ { name: ${gw} } ]
  hostnames: [ "v1.example.com" ]
  rules: [ { matches: [ { path: { type: PathPrefix, value: / } } ], backendRefs: [ { name: echo-v1, port: 80 } ] } ]
EOF
      [ "$test" = host-routing ] && cat <<EOF
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${impl}-host-v2, namespace: ${TEST_NS} }
spec:
  parentRefs: [ { name: ${gw} } ]
  hostnames: [ "v2.example.com" ]
  rules: [ { matches: [ { path: { type: PathPrefix, value: / } } ], backendRefs: [ { name: echo-v2, port: 80 } ] } ]
EOF
      ;;
    path-routing)
      cat <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${impl}-paths, namespace: ${TEST_NS} }
spec:
  parentRefs: [ { name: ${gw} } ]
  hostnames: [ "v1.example.com" ]
  rules:
  - matches: [ { path: { type: PathPrefix, value: /v1 } } ]
    backendRefs: [ { name: echo-v1, port: 80 } ]
  - matches: [ { path: { type: PathPrefix, value: /v2 } } ]
    backendRefs: [ { name: echo-v2, port: 80 } ]
EOF
      ;;
    header-routing)
      cat <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${impl}-header, namespace: ${TEST_NS} }
spec:
  parentRefs: [ { name: ${gw} } ]
  hostnames: [ "v1.example.com" ]
  rules:
  - matches: [ { headers: [ { name: X-Version, value: v1 } ] } ]
    backendRefs: [ { name: echo-v1, port: 80 } ]
  - matches: [ { headers: [ { name: X-Version, value: v2 } ] } ]
    backendRefs: [ { name: echo-v2, port: 80 } ]
EOF
      ;;
    canary-traffic)
      cat <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${impl}-canary, namespace: ${TEST_NS} }
spec:
  parentRefs: [ { name: ${gw} } ]
  hostnames: [ "canary.example.com" ]
  rules:
  - matches: [ { path: { type: PathPrefix, value: / } } ]
    backendRefs:
    - { name: echo-v1, port: 80, weight: 80 }
    - { name: echo-v2, port: 80, weight: 20 }
EOF
      ;;
    header-modifier)
      cat <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${impl}-hdr, namespace: ${TEST_NS} }
spec:
  parentRefs: [ { name: ${gw} } ]
  hostnames: [ "v1.example.com" ]
  rules:
  - matches: [ { path: { type: PathPrefix, value: /hdr } } ]
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier: { set: [ { name: X-Test, value: modified } ] }
    backendRefs: [ { name: echo-v1, port: 80 } ]
EOF
      ;;
    cross-namespace)
      cat <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${impl}-cross, namespace: ${TEST_NS} }
spec:
  parentRefs: [ { name: ${gw} } ]
  hostnames: [ "v1.example.com" ]
  rules:
  - matches: [ { path: { type: PathPrefix, value: /cross } } ]
    backendRefs: [ { name: echo-cross, namespace: gwtest-backend2, port: 80 } ]
EOF
      ;;
    https-redirect)
      cat <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${impl}-redirect, namespace: ${TEST_NS} }
spec:
  parentRefs: [ { name: ${gw} } ]
  hostnames: [ "redirect.example.com" ]
  rules:
  - filters:
    - type: RequestRedirect
      requestRedirect: { scheme: https, statusCode: 301 }
EOF
      ;;
    url-rewrite)
      cat <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${impl}-rewrite, namespace: ${TEST_NS} }
spec:
  parentRefs: [ { name: ${gw} } ]
  hostnames: [ "v1.example.com" ]
  rules:
  - matches: [ { path: { type: PathPrefix, value: /old } } ]
    filters:
    - type: URLRewrite
      urlRewrite: { path: { type: ReplacePrefixMatch, replacePrefixMatch: /new } }
    backendRefs: [ { name: echo-v1, port: 80 } ]
EOF
      ;;
    timeout)
      cat <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${impl}-timeout, namespace: ${TEST_NS} }
spec:
  parentRefs: [ { name: ${gw} } ]
  hostnames: [ "timeout.example.com" ]
  rules:
  - matches: [ { path: { type: PathPrefix, value: / } } ]
    timeouts: { request: 2s }
    backendRefs: [ { name: httpbin, port: 80 } ]
EOF
      ;;
    retry)
      cat <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${impl}-retry, namespace: ${TEST_NS} }
spec:
  parentRefs: [ { name: ${gw} } ]
  hostnames: [ "retry.example.com" ]
  rules:
  - matches: [ { path: { type: PathPrefix, value: / } } ]
    retry: { attempts: 3, codes: [ 503 ] }
    backendRefs: [ { name: httpbin, port: 80 } ]
EOF
      ;;
    health-check)
      cat <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${impl}-hc, namespace: ${TEST_NS} }
spec:
  parentRefs: [ { name: ${gw} } ]
  hostnames: [ "hc.example.com" ]
  rules: [ { matches: [ { path: { type: PathPrefix, value: / } } ], backendRefs: [ { name: hc-backend, port: 80 } ] } ]
EOF
      # 구현체별 능동 health check 정책(지원하는 것만). 없으면 bad 미제거 → unsupported.
      case "$impl" in
        envoy) cat <<EOF
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: BackendTrafficPolicy
metadata: { name: ${impl}-hc, namespace: ${TEST_NS} }
spec:
  targetRefs: [ { group: gateway.networking.k8s.io, kind: HTTPRoute, name: ${impl}-hc } ]
  healthCheck:
    active:
      type: HTTP
      http: { path: /health, expectedStatuses: [ 200 ] }
      interval: 1s
      timeout: 1s
      healthyThreshold: 1
      unhealthyThreshold: 1
EOF
;;
        kgateway) cat <<EOF
---
apiVersion: gateway.kgateway.dev/v1alpha1
kind: BackendConfigPolicy
metadata: { name: ${impl}-hc, namespace: ${TEST_NS} }
spec:
  targetRefs: [ { group: "", kind: Service, name: hc-backend } ]
  healthCheck:
    healthyThreshold: 1
    unhealthyThreshold: 1
    interval: 1s
    timeout: 1s
    http: { path: /health }
EOF
;;
        kong) cat <<EOF
---
apiVersion: configuration.konghq.com/v1beta1
kind: KongUpstreamPolicy
metadata: { name: ${impl}-hc, namespace: ${TEST_NS} }
spec:
  healthchecks:
    active:
      type: http
      httpPath: /health
      healthy: { interval: 1, successes: 1 }
      unhealthy: { interval: 1, httpFailures: 1 }
EOF
;;
      esac
      ;;
    grpc-routing)
      cat <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: GRPCRoute
metadata: { name: ${impl}-grpc, namespace: ${TEST_NS} }
spec:
  parentRefs: [ { name: ${gw} } ]
  hostnames: [ "grpc.example.com" ]
  rules: [ { backendRefs: [ { name: grpc-backend, port: 9000 } ] } ]
EOF
      ;;
    session-affinity)
      cat <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${impl}-sticky, namespace: ${TEST_NS} }
spec:
  parentRefs: [ { name: ${gw} } ]
  hostnames: [ "sticky.example.com" ]
  rules:
  - matches: [ { path: { type: PathPrefix, value: / } } ]
    backendRefs: [ { name: echo-v1, port: 80 } ]
    sessionPersistence: { sessionName: gwsession, type: Cookie }
EOF
      ;;
    backend-tls)
      cat <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: BackendTLSPolicy
metadata: { name: ${impl}-btls, namespace: ${TEST_NS} }
spec:
  targetRefs: [ { group: "", kind: Service, name: backend-tls } ]
  validation:
    caCertificateRefs: [ { group: "", kind: ConfigMap, name: backend-ca } ]
    hostname: backend-tls.local
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${impl}-btls-route, namespace: ${TEST_NS} }
spec:
  parentRefs: [ { name: ${gw} } ]
  hostnames: [ "btls.example.com" ]
  rules:
  - matches: [ { path: { type: PathPrefix, value: / } } ]
    backendRefs: [ { name: backend-tls, port: 443 } ]
EOF
      ;;
    response-header-modifier)
      cat <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${impl}-resphdr, namespace: ${TEST_NS} }
spec:
  parentRefs: [ { name: ${gw} } ]
  hostnames: [ "v1.example.com" ]
  rules:
  - matches: [ { path: { type: PathPrefix, value: /resphdr } } ]
    filters:
    - type: ResponseHeaderModifier
      responseHeaderModifier: { set: [ { name: X-Resp-Test, value: modified } ] }
    backendRefs: [ { name: echo-v1, port: 80 } ]
EOF
      ;;
    request-mirror)
      cat <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${impl}-mirror, namespace: ${TEST_NS} }
spec:
  parentRefs: [ { name: ${gw} } ]
  hostnames: [ "v1.example.com" ]
  rules:
  - matches: [ { path: { type: PathPrefix, value: /mirror } } ]
    filters:
    - type: RequestMirror
      requestMirror: { backendRef: { name: echo-v2, port: 80 } }
    backendRefs: [ { name: echo-v1, port: 80 } ]
EOF
      ;;
    method-matching)
      cat <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${impl}-method, namespace: ${TEST_NS} }
spec:
  parentRefs: [ { name: ${gw} } ]
  hostnames: [ "method.example.com" ]
  rules:
  - matches: [ { method: GET } ]
    backendRefs: [ { name: echo-v1, port: 80 } ]
  - matches: [ { method: POST } ]
    backendRefs: [ { name: echo-v2, port: 80 } ]
EOF
      ;;
    query-param-matching)
      cat <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${impl}-query, namespace: ${TEST_NS} }
spec:
  parentRefs: [ { name: ${gw} } ]
  hostnames: [ "query.example.com" ]
  rules:
  - matches: [ { queryParams: [ { name: ver, value: v1 } ] } ]
    backendRefs: [ { name: echo-v1, port: 80 } ]
  - matches: [ { queryParams: [ { name: ver, value: v2 } ] } ]
    backendRefs: [ { name: echo-v2, port: 80 } ]
EOF
      ;;
    backend-request-header-mod)
      cat <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${impl}-bereqhdr, namespace: ${TEST_NS} }
spec:
  parentRefs: [ { name: ${gw} } ]
  hostnames: [ "v1.example.com" ]
  rules:
  - matches: [ { path: { type: PathPrefix, value: /bereqhdr } } ]
    backendRefs:
    - name: echo-v1
      port: 80
      filters:
      - type: RequestHeaderModifier
        requestHeaderModifier: { set: [ { name: X-Backend-Inject, value: injected } ] }
EOF
      ;;
    path-redirect)
      cat <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${impl}-predirect, namespace: ${TEST_NS} }
spec:
  parentRefs: [ { name: ${gw} } ]
  hostnames: [ "predirect.example.com" ]
  rules:
  - filters:
    - type: RequestRedirect
      requestRedirect: { path: { type: ReplaceFullPath, replaceFullPath: /newpath }, statusCode: 302 }
EOF
      ;;
    websocket)
      cat <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${impl}-ws, namespace: ${TEST_NS} }
spec:
  parentRefs: [ { name: ${gw} } ]
  hostnames: [ "ws.example.com" ]
  rules:
  - matches: [ { path: { type: PathPrefix, value: / } } ]
    backendRefs: [ { name: ws-backend, port: 80 } ]
EOF
      ;;
    regex)
      cat <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${impl}-regex, namespace: ${TEST_NS} }
spec:
  parentRefs: [ { name: ${gw} } ]
  hostnames: [ "regex.example.com" ]
  rules:
  - matches: [ { path: { type: RegularExpression, value: "/api/v[0-9]+/.*" } } ]
    backendRefs: [ { name: echo-v1, port: 80 } ]
EOF
      ;;
    cors)
      cat <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${impl}-cors, namespace: ${TEST_NS} }
spec:
  parentRefs: [ { name: ${gw} } ]
  hostnames: [ "cors.example.com" ]
  rules:
  - matches: [ { path: { type: PathPrefix, value: / } } ]
    filters:
    - type: CORS
      cors:
        allowOrigins: [ "https://example.test" ]
        allowMethods: [ GET, POST ]
    backendRefs: [ { name: echo-v1, port: 80 } ]
EOF
      ;;
  esac
}

# 벤더 정책 라이브러리(매트릭스 실측). policy_for impl kind → 라우트+벤더정책 YAML.
# kind: rate-limit | body-size. 검증된 스키마(EXPANSION_STATE 3·4절). 라우트 호스트:
#   rate-limit=rl.example.com, body-size=bsize.example.com. kong/traefik은 ExtensionRef 필터.
policy_for() {
  local impl="$1" kind="$2" gw="${impl}-gw" host route filt grp pkind
  case "$kind" in
    rate-limit) host=rl.example.com; route="${impl}-rl" ;;
    body-size)  host=bsize.example.com; route="${impl}-bsize" ;;
    ip-filter)  host=ipf.example.com; route="${impl}-ipf" ;;
    basic-auth) host=bauth.example.com; route="${impl}-bauth" ;;
    *) return 0 ;;
  esac
  # ExtensionRef 필터(kong/traefik/nginx) — 정책 종류별 group/kind/name
  filt=""
  case "$impl:$kind" in
    kong:rate-limit|kong:body-size|kong:ip-filter|kong:basic-auth) \
      filt='filters: [ { type: ExtensionRef, extensionRef: { group: configuration.konghq.com, kind: KongPlugin, name: '"$route"' } } ],' ;;
    traefik:rate-limit|traefik:body-size|traefik:ip-filter|traefik:basic-auth) \
      filt='filters: [ { type: ExtensionRef, extensionRef: { group: traefik.io, kind: Middleware, name: '"$route"' } } ],' ;;
    nginx:basic-auth) \
      filt='filters: [ { type: ExtensionRef, extensionRef: { group: gateway.nginx.org, kind: AuthenticationFilter, name: '"$route"' } } ],' ;;
  esac
  cat <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${route}, namespace: ${TEST_NS} }
spec:
  parentRefs: [ { name: ${gw} } ]
  hostnames: [ "${host}" ]
  rules: [ { matches: [ { path: { type: PathPrefix, value: / } } ], ${filt} backendRefs: [ { name: echo-v1, port: 80 } ] } ]
EOF
  case "$impl:$kind" in
    envoy:rate-limit) cat <<EOF
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: BackendTrafficPolicy
metadata: { name: ${route}, namespace: ${TEST_NS} }
spec:
  targetRefs: [ { group: gateway.networking.k8s.io, kind: HTTPRoute, name: ${route} } ]
  rateLimit: { type: Local, local: { rules: [ { limit: { requests: 5, unit: Minute } } ] } }
EOF
;;
    kgateway:rate-limit) cat <<EOF
---
apiVersion: gateway.kgateway.dev/v1alpha1
kind: TrafficPolicy
metadata: { name: ${route}, namespace: ${TEST_NS} }
spec:
  targetRefs: [ { group: gateway.networking.k8s.io, kind: HTTPRoute, name: ${route} } ]
  rateLimit: { local: { tokenBucket: { maxTokens: 5, tokensPerFill: 5, fillInterval: 60s } } }
EOF
;;
    nginx:rate-limit) cat <<EOF
---
apiVersion: gateway.nginx.org/v1alpha1
kind: RateLimitPolicy
metadata: { name: ${route}, namespace: ${TEST_NS} }
spec:
  targetRefs: [ { group: gateway.networking.k8s.io, kind: HTTPRoute, name: ${route} } ]
  rateLimit: { rejectCode: 429, local: { rules: [ { key: "\$binary_remote_addr", rate: "5r/m", zoneSize: "1m" } ] } }
EOF
;;
    kong:rate-limit) cat <<EOF
---
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata: { name: ${route}, namespace: ${TEST_NS} }
plugin: rate-limiting
config: { minute: 5, policy: local }
EOF
;;
    traefik:rate-limit) cat <<EOF
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata: { name: ${route}, namespace: ${TEST_NS} }
spec:
  rateLimit: { average: 5, burst: 1, period: 1m }
EOF
;;
    istio:rate-limit) cat <<EOF
---
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata: { name: ${route}, namespace: ${TEST_NS} }
spec:
  configPatches:
  - applyTo: HTTP_FILTER
    match: { context: GATEWAY, listener: { filterChain: { filter: { name: "envoy.filters.network.http_connection_manager" } } } }
    patch:
      operation: INSERT_BEFORE
      value:
        name: envoy.filters.http.local_ratelimit
        typed_config:
          "@type": type.googleapis.com/udpa.type.v1.TypedStruct
          type_url: type.googleapis.com/envoy.extensions.filters.http.local_ratelimit.v3.LocalRateLimit
          value:
            stat_prefix: http_local_rate_limiter
            token_bucket: { max_tokens: 5, tokens_per_fill: 5, fill_interval: 60s }
            filter_enabled: { default_value: { numerator: 100, denominator: HUNDRED } }
            filter_enforced: { default_value: { numerator: 100, denominator: HUNDRED } }
EOF
;;
    nginx:body-size) cat <<EOF
---
apiVersion: gateway.nginx.org/v1alpha1
kind: ClientSettingsPolicy
metadata: { name: ${route}, namespace: ${TEST_NS} }
spec:
  targetRefs: [ { group: gateway.networking.k8s.io, kind: HTTPRoute, name: ${route} } ]
  body: { maxSize: "1k" }
EOF
;;
    traefik:body-size) cat <<EOF
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata: { name: ${route}, namespace: ${TEST_NS} }
spec:
  buffering: { maxRequestBodyBytes: 1024 }
EOF
;;
    kong:body-size) cat <<EOF
---
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata: { name: ${route}, namespace: ${TEST_NS} }
plugin: request-size-limiting
config: { allowed_payload_size: 1 }
EOF
;;
    istio:body-size) cat <<EOF
---
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata: { name: ${route}, namespace: ${TEST_NS} }
spec:
  configPatches:
  - applyTo: HTTP_FILTER
    match: { context: GATEWAY, listener: { filterChain: { filter: { name: "envoy.filters.network.http_connection_manager" } } } }
    patch:
      operation: INSERT_BEFORE
      value:
        name: envoy.filters.http.buffer
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.http.buffer.v3.Buffer
          max_request_bytes: 1024
EOF
;;
    # ---- basic-auth (벤더; auth-type basic 대체) ----
    envoy:basic-auth) cat <<EOF
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata: { name: ${route}, namespace: ${TEST_NS} }
spec:
  targetRefs: [ { group: gateway.networking.k8s.io, kind: HTTPRoute, name: ${route} } ]
  basicAuth: { users: { name: ba-envoy } }
EOF
;;
    traefik:basic-auth) cat <<EOF
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata: { name: ${route}, namespace: ${TEST_NS} }
spec:
  basicAuth: { secret: ba-traefik }
EOF
;;
    kong:basic-auth) cat <<EOF
---
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata: { name: ${route}, namespace: ${TEST_NS} }
plugin: basic-auth
EOF
;;
    kgateway:basic-auth) cat <<EOF
---
apiVersion: gateway.kgateway.dev/v1alpha1
kind: TrafficPolicy
metadata: { name: ${route}, namespace: ${TEST_NS} }
spec:
  targetRefs: [ { group: gateway.networking.k8s.io, kind: HTTPRoute, name: ${route} } ]
  basicAuth:
    secretRef: { name: ba-envoy }
EOF
;;
    nginx:basic-auth) cat <<EOF
---
apiVersion: gateway.nginx.org/v1alpha1
kind: AuthenticationFilter
metadata: { name: ${route}, namespace: ${TEST_NS} }
spec:
  type: Basic
  basic: { realm: "gwtest", secretRef: { name: ba-nginx } }
EOF
;;
    # ---- ip-filter (벤더; whitelist-source-range 대체. 허용 CIDR을 클라 미포함으로 → 차단) ----
    envoy:ip-filter) cat <<EOF
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata: { name: ${route}, namespace: ${TEST_NS} }
spec:
  targetRefs: [ { group: gateway.networking.k8s.io, kind: HTTPRoute, name: ${route} } ]
  authorization:
    defaultAction: Deny
    rules: [ { name: allowcidr, action: Allow, principal: { clientCIDRs: [ "10.255.255.0/24" ] } } ]
EOF
;;
    istio:ip-filter) cat <<EOF
---
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata: { name: ${route}, namespace: ${TEST_NS} }
spec:
  targetRefs: [ { group: gateway.networking.k8s.io, kind: Gateway, name: ${gw} } ]
  action: ALLOW
  rules: [ { from: [ { source: { ipBlocks: [ "10.255.255.0/24" ] } } ] } ]
EOF
;;
    traefik:ip-filter) cat <<EOF
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata: { name: ${route}, namespace: ${TEST_NS} }
spec:
  ipAllowList: { sourceRange: [ "10.255.255.0/24" ] }
EOF
;;
    kong:ip-filter) cat <<EOF
---
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata: { name: ${route}, namespace: ${TEST_NS} }
plugin: ip-restriction
config: { allow: [ "10.255.255.0/24" ] }
EOF
;;
  esac
}
export -f policy_for

# 배치 배포(비-Kong): 라우트 생성 테스트들을 한 번에 apply.
ROUTE_TESTS="host-routing path-routing header-routing canary-traffic header-modifier \
cross-namespace https-redirect url-rewrite timeout grpc-routing session-affinity backend-tls"
deploy_batch_routes() {
  local impl="$1" t
  for t in $ROUTE_TESTS; do routes_for "$impl" "$t"; echo "---"; done | kc apply -f - >/dev/null 2>&1 || true
}

# Gateway LB IP 동적 발견(하드코딩 제거). status.addresses 우선, 실패 시 Service.
discover_ip() {
  local impl="$1" ip="" i
  for i in $(seq 1 30); do
    ip="$(kc -n "$TEST_NS" get gateway "${impl}-gw" \
          -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)"
    [ -n "$ip" ] && { echo "$ip"; return 0; }
    # Traefik: per-gateway Service가 아니라 traefik ns의 프록시 LB Service에 IP가 있음
    if [ "$impl" = traefik ]; then
      ip="$(kc -n traefik get svc traefik \
            -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
      [ -n "$ip" ] && { echo "$ip"; return 0; }
    fi
    sleep 5
  done
  echo ""   # 못 찾음 → 호출부가 infra-excluded 처리
}

#=== HTTP 헬퍼: 클라이언트 파드서 curl (export 되어 lib-tests 가 사용) ===
# LB L2 전파 중 일시적 연결 끊김(curl exit 7)을 흡수하기 위해 빈 응답이면 재시도.
gw_curl() {
  local i out
  for i in 1 2 3; do
    out="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -s --max-time 8 "$@" 2>/dev/null)"
    [ -n "$out" ] && { printf '%s' "$out"; return 0; }
    sleep 2
  done
  printf '%s' "$out"
}
export -f gw_curl

# 게이트웨이 데이터플레인이 기본 라우트를 프로그래밍할 때까지 대기(테스트 전).
# IP 발급 ≠ 라우팅 준비. 기본 host 라우트가 백엔드를 반환할 때까지 폴링(~300s).
# Kong managed gateway는 ControlPlane+DataPlane 프로비저닝이 무거워 시간이 더 걸림.
wait_routing_ready() {
  local i r
  for i in $(seq 1 60); do
    r="$(gw_curl -H "Host: $DOMAIN_V1" "http://$GW_IP/" 2>/dev/null)"
    echo "$r" | grep -q "$BACKEND_V1_TOKEN" && return 0
    sleep 5
  done
  return 1
}

# 두 백엔드(v1·v2)가 모두 정확히 프로그래밍될 때까지 대기. 멀티룰 라우팅에서
# 둘째 rule 반영이 늦는 구현체(Kong/Traefik 등)의 전이 race를 측정에서 배제한다.
# 한쪽(v1)만 폴링하면 다른 rule이 아직 안 올라온 채로 테스트가 발사돼 헛fail.
# 본문 토큰까지 확인(코드만으론 /v2가 200이지만 v1로 잘못 가는 전이상태를 못 거름).
_await_two() {  # h1 e1 p1 tok1  h2 e2 p2 tok2
  local h1="$1" e1="$2" p1="$3" k1="$4" h2="$5" e2="$6" p2="$7" k2="$8" i r1 r2 ok=0
  # 연속 2회 안정 통과를 요구한다. NGF 등은 라우트 변경마다 dataplane 전체 리로드를
  # 하는데(특히 워밍업 route 삭제 직후 같은 route 재배포가 겹치면), 일시적 ready를
  # 한 번 잡은 직후 리로드가 착지해 테스트가 404를 맞는 플레이크가 있었다(nginx
  # host-routing). 연속 성공을 요구하면 리로드가 가라앉은 정상상태에서만 진행한다.
  for i in $(seq 1 40); do                               # ~80s(연속요구로 여유)
    r1="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -s --max-time 4 -H "Host: $h1" $e1 "http://$GW_IP$p1" 2>/dev/null || true)"
    r2="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -s --max-time 4 -H "Host: $h2" $e2 "http://$GW_IP$p2" 2>/dev/null || true)"
    if echo "$r1" | grep -q "$k1" && echo "$r2" | grep -q "$k2"; then
      ok=$((ok+1)); [ "$ok" -ge 2 ] && return 0
    else
      ok=0
    fi
    sleep 2
  done
  return 1
}

# 테스트별 라우트 데이터패스 준비 폴링(격리 모드, 7종 동일). 미지원이면 timeout→fail로 기록.
route_ready() {
  local t="$1" host=v1.example.com path=/ extra="" want_redirect=0 i code
  case "$t" in
    # 멀티룰/멀티라우트: 양쪽 백엔드가 정확히 프로그래밍될 때까지 대기(전이 race 배제).
    host-routing)   _await_two "$DOMAIN_V1" "" / "$BACKEND_V1_TOKEN" "$DOMAIN_V2" "" / "$BACKEND_V2_TOKEN"; return ;;
    path-routing)   _await_two "$DOMAIN_V1" "" /v1 "$BACKEND_V1_TOKEN" "$DOMAIN_V1" "" /v2 "$BACKEND_V2_TOKEN"; return ;;
    header-routing) _await_two "$DOMAIN_V1" "-H X-Version:v1" / "$BACKEND_V1_TOKEN" "$DOMAIN_V1" "-H X-Version:v2" / "$BACKEND_V2_TOKEN"; return ;;
    header-modifier) path=/hdr ;;
    cross-namespace) path=/cross ;;
    url-rewrite) path=/old ;;
    canary-traffic) host=canary.example.com ;;
    https-redirect) host=redirect.example.com; want_redirect=1 ;;
    session-affinity) host=sticky.example.com ;;
    backend-tls) host=btls.example.com ;;
    response-header-modifier) path=/resphdr ;;
    request-mirror) path=/mirror ;;
    backend-request-header-mod) path=/bereqhdr ;;
    method-matching) host=method.example.com ;;
    query-param-matching) host=query.example.com; path="/?ver=v1" ;;
    websocket) host=ws.example.com ;;
    regex) host=regex.example.com; path=/api/v1/x ;;
    cors) host=cors.example.com ;;
    path-redirect) host=predirect.example.com; want_redirect=1 ;;
    timeout|grpc-routing) sleep 12; return 0 ;;          # 특수(지연/h2c) → 고정 대기
    retry|health-check) sleep 2; return 0 ;;             # 라우트 없음(스텁)
    # 자체완결 테스트(자체 게이트웨이/정책 배포) → 표준 라우트 준비대기 불필요(테스트 내부서 처리)
    listener-isolation|rate-limiting|body-size|auth-jwt|auth-extauth|ip-filter|basic-auth|mtls-client|tls-passthrough) sleep 2; return 0 ;;
  esac
  local ok=0 good
  for i in $(seq 1 24); do                               # ~48s(연속 2회 요구)
    code="$(kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -s -o /dev/null -w '%{http_code}' \
            --max-time 4 -H "Host: $host" $extra "http://$GW_IP$path" 2>/dev/null || echo 000)"
    good=0
    if [ "$want_redirect" = 1 ]; then
      [ "${code:0:2}" = "30" ] && good=1
    else
      [ -n "$code" ] && [ "$code" != "404" ] && [ "$code" != "000" ] && good=1
    fi
    if [ "$good" = 1 ]; then ok=$((ok+1)); [ "$ok" -ge 2 ] && return 0; else ok=0; fi
    sleep 2
  done
  return 1
}

# RAW 기록(AIOps 참고): 배포한 라우트 YAML + 대표 응답을 RAW_DIR/<impl>/ 에 저장(감사용).
capture_raw() {
  [ -z "${RAW_DIR:-}" ] && return 0
  local impl="$1" t="$2" d="$RAW_DIR/$impl" host=v1.example.com path=/
  mkdir -p "$d"
  routes_for "$impl" "$t" > "$d/${t}.route.yaml" 2>/dev/null || true
  case "$t" in
    canary-traffic) host=canary.example.com ;;
    https-redirect) host=redirect.example.com ;;
    timeout) host=timeout.example.com ;;
    session-affinity) host=sticky.example.com ;;
    backend-tls) host=btls.example.com ;;
    path-routing) path=/v1 ;;
    header-modifier) path=/hdr ;;
    cross-namespace) path=/cross ;;
    url-rewrite) path=/old ;;
  esac
  local i
  if [ "$t" = grpc-routing ]; then
    kc -n "$TEST_NS" exec "$CLIENT_POD" -- grpcurl -plaintext -authority grpc.example.com \
      -max-time 6 "$GW_IP:80" list > "$d/${t}.response" 2>&1 || true
  else
    for i in 1 2 3; do   # 일시 끊김(exit 7) 흡수
      kc -n "$TEST_NS" exec "$CLIENT_POD" -- curl -sik --max-time 6 -H "Host: $host" \
        "http://$GW_IP$path" > "$d/${t}.response" 2>&1 && break
      sleep 2
    done
  fi
}

# 견고성 축(7종 동일 잣대): 모든 기능 라우트를 한꺼번에 배포 후 기본 host-routing 생존 확인.
# 6종은 robust, Kong은 all-or-nothing으로 fragile.
_cleanup_batch() {
  local impl="$1" t
  for t in $ROUTE_TESTS; do routes_for "$impl" "$t"; echo "---"; done \
    | kc delete -f - --ignore-not-found >/dev/null 2>&1 || true
}
check_robustness() {
  local impl="$1" i r
  deploy_batch_routes "$impl"
  for i in $(seq 1 12); do
    r="$(gw_curl -H "Host: $DOMAIN_V1" "http://$GW_IP/" 2>/dev/null)"
    echo "$r" | grep -q "$BACKEND_V1_TOKEN" && { _cleanup_batch "$impl"; echo robust; return 0; }
    sleep 5
  done
  _cleanup_batch "$impl"
  echo fragile
}

#=== 라운드 실행 ===
main() {
  # RAW 기록 디렉토리(라운드별). gitignore 대상.
  RAW_DIR="$(cd "$HERE/.." && pwd)/results/raw/round-${ROUND}"
  mkdir -p "$RAW_DIR"; export RAW_DIR
  echo "RAW: $RAW_DIR"

  deploy_fixtures
  # 디버깅 시 KEEP_FIXTURES=1 로 정리 건너뜀(반복 빠르게)
  [ "${KEEP_FIXTURES:-0}" = 1 ] || trap teardown_fixtures EXIT

  local impl_json_list="[]"
  for impl in $IMPLS; do
    echo "============ ${impl} ============"
    local gwclass; gwclass="$(gwclass_of "$impl")"
    # GatewayClass 준비 확인(install 안 됐으면 전체 infra-excluded)
    if ! kc get gatewayclass "$gwclass" >/dev/null 2>&1; then
      echo "  GatewayClass '$gwclass' 없음 → 전 항목 infra-excluded"
      impl_json_list="$(append_impl "$impl_json_list" "$impl" "" "infra-excluded-all")"
      continue
    fi
    deploy_gateway "$impl"
    local ip; ip="$(discover_ip "$impl")"
    if [ -z "$ip" ]; then
      echo "  LB IP 미발견 → 전 항목 infra-excluded"
      impl_json_list="$(append_impl "$impl_json_list" "$impl" "" "infra-excluded-all")"
      continue
    fi
    echo "  IP=$ip"
    export GW_IP="$ip" GW_IMPL="$impl"

    # 데이터플레인 콜드스타트 워밍업: 첫 라우트 프로그래밍이 느려 초반 테스트가
    # 헛fail될 수 있다. host 라우트로 한 번 데운 뒤(최대 300s) 삭제하고 본 측정 시작.
    routes_for "$impl" host-routing | kc apply -f - >/dev/null 2>&1 || true
    if wait_routing_ready; then echo "  워밍업 완료(데이터플레인 준비)"; else echo "  워밍업 타임아웃(계속)"; fi
    routes_for "$impl" host-routing | kc delete -f - --ignore-not-found >/dev/null 2>&1 || true

    # 방식 가: 7종 전부 동일하게 기능별 격리(테스트마다 라우트 배포→준비대기→테스트→삭제).
    # Kong 특별취급 없음. 결과 차이는 각 구현체 자체 특성에서 자연 발생.
    echo "  [격리 모드] 테스트별 라우트 배포→대기→RAW기록→테스트→삭제"
    local tests_json="[]" out t
    for t in $TESTS; do
      routes_for "$impl" "$t" | kc apply -f - >/dev/null 2>&1 || true
      route_ready "$t" || true
      capture_raw "$impl" "$t"
      out="$(run_one_test "$t")"
      routes_for "$impl" "$t" | kc delete -f - --ignore-not-found >/dev/null 2>&1 || true
      tests_json="$(add_test_result "$tests_json" "$t" "$out")"
    done
    # 견고성 축(7종 동일 잣대): 모든 기능 동시 배포 시 기본 라우팅 생존 여부
    local robust; robust="$(check_robustness "$impl")"
    echo "  config-robustness: $robust"
    tests_json="$(add_test_result "$tests_json" "config-robustness" \
      "$([ "$robust" = robust ] && echo pass || echo fail)||{}")"

    # 클러스터 스냅샷 RAW(현 상태)
    [ -n "${RAW_DIR:-}" ] && kc -n "$TEST_NS" get gateway "${impl}-gw" -o yaml \
      > "$RAW_DIR/$impl/gateway-snapshot.yaml" 2>/dev/null || true

    impl_json_list="$(append_impl "$impl_json_list" "$impl" "$ip" "$tests_json")"

    # impl별 격리 강화: 측정 끝난 gateway/dataplane를 즉시 정리해, 다음 impl 측정 시
    # 한 번에 하나의 dataplane만 떠 있게 한다(라운드 내 dataplane 누적 자원경합 제거).
    # 스냅샷 복원은 PoC엔 과해 미채택. Traefik/Cilium은 공유 dataplane이라 Gateway
    # 삭제로 프록시가 사라지진 않으나 무해. 다음 impl의 deploy+warmup이 종료 지연 흡수.
    kc -n "$TEST_NS" delete gateway "${impl}-gw" --ignore-not-found >/dev/null 2>&1 || true
    sleep 5
  done

  emit_round "$impl_json_list"
}

main "$@"
