#!/usr/bin/env bash
# v1.5.0 + K8s 1.37.0 재측정 전체 체인 (2026-08-31 기동, 1회용).
# 순서: [1] MCP 축 재확인 -> [2] A2A 프로브 -> [3] 경로 쌍 -> [4] guardrail
# 교대 50셀 -> [5] A2A 세 경로 20회차. 단계 실패 시 중단(다음 단계 미기동).
# 게이트웨이/백엔드는 상주(각 단계 rv 사본이 제거하지 않음).
# 예상: [1]~[4] 약 5시간, [5] 약 14시간 -> 화요일 오전 종료.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
REPO="$(cd "$STUDY/.." && pwd)"
A2A="$REPO/a2a-study"
PY="$HOME/.venvs/mcpbench/bin/python"
log() { echo "[chain $(date '+%m-%d %H:%M')] $*"; }
push() { ( cd "$REPO" && git add agentgateway-study/runs a2a-study/runs >/dev/null 2>&1 \
  && git commit -q -m "rv 체인: $1" >/dev/null 2>&1 \
  && git pull --rebase --autostash -q origin main >/dev/null 2>&1 \
  && git push -q origin main >/dev/null 2>&1 ) || true; }
run_stage() { # run_stage <이름> <작업디렉토리> <명령...>
  local name="$1" wd="$2"; shift 2
  log "=== 단계 시작: $name ==="
  ( cd "$wd" && "$@" )
  local rc=$?
  if [ $rc -ne 0 ]; then
    log "=== 단계 실패($rc): $name. 체인 중단 ==="
    push "단계 실패 $name"
    exit $rc
  fi
  log "=== 단계 완료: $name ==="
  push "단계 완료 $name"
}

run_stage "MCP 축 재확인" "$STUDY" ./harness/rv_run_axes.sh "$PY" runs/rv-axes-0831
run_stage "A2A 프로브"    "$A2A"   ./harness/rv_probes.sh runs/rv-probes-0831
run_stage "경로 쌍"       "$STUDY" ./harness/rv_run_ab.sh "$PY" runs/rv-ab-0831
run_stage "guardrail 교대" "$STUDY" ./harness/rv_gr_matrix.sh runs/rv-grm-0831
run_stage "A2A 세 경로 20회차" "$A2A"   ./harness/rv_ab_matrix.sh runs/rv-abm-0831 1 20
log "=== 체인 전체 종료 ==="
push "체인 전체 종료"
