#!/usr/bin/env bash
# rv 재측정 체인 2 (배터리 사고 후 재기동, 단계 4~5만).
# 전제: 클러스터/게이트웨이/백엔드 상주, AC 전원. 단계 실패 시 중단.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
REPO="$(cd "$STUDY/.." && pwd)"
A2A="$REPO/a2a-study"
log() { echo "[chain2 $(date '+%m-%d %H:%M')] $*"; }
push() { ( cd "$REPO" && git add agentgateway-study/runs a2a-study/runs >/dev/null 2>&1 \
  && git commit -q -m "rv 체인2: $1" >/dev/null 2>&1 \
  && git pull --rebase --autostash -q origin main >/dev/null 2>&1 \
  && git push -q origin main >/dev/null 2>&1 ) || true; }
# AC 전원 가드 (배터리 사고 재발 방지)
pmset -g batt | grep -q 'AC Power' || { log "AC 전원 아님. 중단"; exit 1; }
run_stage() {
  local name="$1" wd="$2"; shift 2
  log "=== 단계 시작: $name ==="
  ( cd "$wd" && "$@" ); local rc=$?
  if [ $rc -ne 0 ]; then log "=== 단계 실패($rc): $name. 체인 중단 ==="; push "단계 실패 $name"; exit $rc; fi
  log "=== 단계 완료: $name ==="; push "단계 완료 $name"
}
run_stage "guardrail 교대(재)" "$STUDY" ./harness/rv_gr_matrix.sh runs/rv-grm-0831b
run_stage "A2A 세 경로 20회차"    "$A2A"   ./harness/rv_ab_matrix.sh runs/rv-abm-0831 1 20
log "=== 체인2 전체 종료 ==="
push "체인2 전체 종료"
