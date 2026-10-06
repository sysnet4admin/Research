#!/usr/bin/env bash
# Q10 2번(3라운드 비교) 결정론 축 재측정 체인(2026-10-06, M4, aaif-benchmark, agentgateway v1.6.0).
# 순서: 축 1/2(P0~P4, T1/T2) -> P3 보강 -> guardrail 결정론(G3, FailOpen) -> extAuth/extProc 결정론.
# 9/2~9/9 v1.5.0 재측정에서 완주한 러너의 버전만 바꾼 사본을 차례로 부른다. 단계 실패는 기록하고 다음으로 넘어간다.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; STUDY="$(cd "$DIR/.." && pwd)"; REPO="$(cd "$STUDY/.." && pwd)"
PY="$HOME/.venvs/mcpbench/bin/python"
log() { echo "[q10 $(date '+%m-%d %H:%M:%S')] $*"; }
push() { ( cd "$REPO" && git add agentgateway-study/runs >/dev/null 2>&1 && git commit -qm "agentgateway-study: Q10 체인 $1" >/dev/null 2>&1 \
  && env -u GITHUB_TOKEN git pull -q --rebase --autostash origin main >/dev/null 2>&1 && env -u GITHUB_TOKEN git push -q origin main >/dev/null 2>&1 ) || true; }
stage() { local name="$1"; shift; log "단계 $name 시작"; ( cd "$STUDY" && "$@" ); local rc=$?; log "단계 $name 끝 rc=$rc"; push "$name rc=$rc"; }
stage axes   ./harness/rv_axes_1006.sh "$PY" runs/q10-axes-1006
stage p3sup  ./harness/rv_p3sup_1006.sh "$PY" runs/q10-p3sup-1006
stage g3     ./harness/rv_g3.sh runs/q10-g3-1006
stage extdet ./harness/rv_extdet.sh runs/q10-extdet-1006
log "=== 체인 완료 ==="
