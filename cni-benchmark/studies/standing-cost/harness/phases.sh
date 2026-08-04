#!/usr/bin/env bash
# 측정 페이즈 6개. 러너가 조건 설치 후 순서대로 호출한다.
# 모든 부하는 kubectl 기반 결정론 루프 (외부 도구 의존 없음, 무인 신뢰성 우선).
# 페이즈 라벨은 $PHASE_FILE에 기록해 수집기가 시계열에 표기한다.

set -euo pipefail

CTX="cni-benchmark"
PHASE_FILE="${PHASE_FILE:?PHASE_FILE 필요}"
WORK_NS="loadwork"

k() { kubectl --context "$CTX" "$@"; }
set_phase() { echo "$1" > "$PHASE_FILE"; echo "[phase] $1 ($(date +%H:%M:%S))"; }

prep_ns() {
  # Terminating 중이면 완전 삭제 대기 (이름 재사용 충돌 방지)
  local start=$SECONDS
  while k get ns "$WORK_NS" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q Terminating; do
    [ $((SECONDS - start)) -gt 180 ] && break
    sleep 5
  done
  k create ns "$WORK_NS" --dry-run=client -o yaml | k apply -f - >/dev/null
}

phase_idle() { # phase_idle <seconds>
  set_phase "idle"
  sleep "$1"
}

phase_density() { # phase_density <seconds> : 파드 0 -> 20 -> 40 -> 60 단계 상승
  set_phase "density"
  prep_ns
  k -n "$WORK_NS" apply -f - <<'EOF' >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata: { name: dense }
spec:
  replicas: 0
  selector: { matchLabels: { app: dense } }
  template:
    metadata: { labels: { app: dense } }
    spec:
      containers:
        - name: pause
          image: registry.k8s.io/pause:3.10
          resources: { requests: { cpu: 5m, memory: 8Mi } }
EOF
  local per_step=$(( $1 / 4 ))
  for n in 20 40 60; do
    k -n "$WORK_NS" scale deploy/dense --replicas=$n >/dev/null
    k -n "$WORK_NS" rollout status deploy/dense --timeout=180s >/dev/null 2>&1 || true
    sleep "$per_step"
  done
  sleep "$per_step"
  # 파드는 유지한 채 다음 페이즈로 (밀도 상태에서 정책/서비스 측정이 현실적)
}

phase_policy() { # phase_policy <seconds> : NetworkPolicy 0 -> 50 -> 100
  set_phase "policy"
  prep_ns
  local half=$(( $1 / 2 ))
  for batch in 1 2; do
    local start=$(( (batch-1)*50 + 1 )) end=$(( batch*50 ))
    for i in $(seq $start $end); do
      k -n "$WORK_NS" apply -f - <<EOF >/dev/null
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: np-$i }
spec:
  podSelector: { matchLabels: { app: dense } }
  ingress:
    - from:
        - podSelector: { matchLabels: { np-peer: "g$i" } }
      ports:
        - { protocol: TCP, port: $((8000 + i)) }
EOF
    done
    sleep "$half"
  done
}

phase_service() { # phase_service <seconds> : Service 0 -> 100 -> 200 (엔드포인트 있는 셀렉터)
  set_phase "service"
  prep_ns
  local half=$(( $1 / 2 ))
  for batch in 1 2; do
    local start=$(( (batch-1)*100 + 1 )) end=$(( batch*100 ))
    for i in $(seq $start $end); do
      k -n "$WORK_NS" apply -f - <<EOF >/dev/null
apiVersion: v1
kind: Service
metadata: { name: svc-$i }
spec:
  selector: { app: dense }
  ports:
    - { port: $((9000 + i % 999)), targetPort: 80, protocol: TCP }
EOF
    done
    sleep "$half"
  done
}

phase_churn() { # phase_churn <seconds> : 20초 주기로 파드 10개 삭제(재생성 유발)
  set_phase "churn"
  prep_ns
  local deadline=$(( SECONDS + $1 ))
  while [ $SECONDS -lt $deadline ]; do
    k -n "$WORK_NS" get pods -l app=dense -o name 2>/dev/null | head -10 \
      | xargs -r kubectl --context "$CTX" -n "$WORK_NS" delete --wait=false >/dev/null 2>&1 || true
    sleep 20
  done
  k -n "$WORK_NS" rollout status deploy/dense --timeout=180s >/dev/null 2>&1 || true
}

phase_node() { # phase_node <seconds> : w2 drain -> 재합류
  set_phase "node"
  k drain w2-k8s --ignore-daemonsets --delete-emptydir-data --force --timeout=180s >/dev/null 2>&1 || true
  sleep $(( $1 / 2 ))
  k uncordon w2-k8s >/dev/null 2>&1 || true
  sleep $(( $1 / 2 ))
}

phase_cleanup() {
  set_phase "cleanup"
  k delete ns "$WORK_NS" --wait=false >/dev/null 2>&1 || true
  set_phase "done"
}

# 단독 실행 지원: phases.sh <phase이름> <seconds>
if [ "${1:-}" != "" ]; then
  "phase_$1" "${2:-60}"
fi
