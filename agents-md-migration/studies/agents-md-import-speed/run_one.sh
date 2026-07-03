#!/usr/bin/env bash
# run_one.sh: 한 회차(조건 x 시나리오) 실행. 독립 러너.
#
# AIOps run.sh를 재사용하지 않는 이유(2026-07-02 결정): run.sh는 PROMPT.md 경로가
# 하드코딩이라 컨텍스트명이 치환된 이 연구용 PROMPT를 읽게 할 수 없다. claude 호출
# 로직만 여기 독립 구현하고, 채점(collect.py)과 audit 캡처(scripts/capture_audit.sh
# 심링크)는 계속 AIOps 것을 재사용한다.
#
# Usage: ./run_one.sh <A|B|C> <scenario-slug> <rep-tag>
#   예:  ./run_one.sh B 001-crashloop r1
#
# Env: CLAUDE_MODEL(기본 claude-sonnet-4-6), TIMEOUT(기본 3600), SKIP_RESET=1(개발용)

set -uo pipefail

COND="${1:?Usage: $0 <A|B|C> <scenario-slug> <rep-tag>}"
SCENARIO="${2:?Usage: $0 <A|B|C> <scenario-slug> <rep-tag>}"
TAG="${3:?Usage: $0 <A|B|C> <scenario-slug> <rep-tag>}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CLUSTER_DIR="$ROOT/test-cluster"
VARIANTS="$ROOT/variants/$COND"
CTX="agents-md-migration"

MODEL="${CLAUDE_MODEL:-claude-sonnet-4-6}"
TIMEOUT="${TIMEOUT:-3600}"

case "$COND" in
  A) VARIANTS="$ROOT/variants/A-claude-native" ;;
  B) VARIANTS="$ROOT/variants/B-agents-import" ;;
  C) VARIANTS="$ROOT/variants/C-symlink" ;;
  *) echo "Error: cond must be A|B|C" >&2; exit 1 ;;
esac

ITER="agentsmd-${COND}-${SCENARIO}-${TAG}"
OUT_DIR="$HERE/runs/$ITER"
WORK="/tmp/claude-$ITER"

mkdir -p "$OUT_DIR"

echo "[$ITER] === start $(date +%T) (model=$MODEL timeout=${TIMEOUT}s) ==="

# 1) 클러스터 리셋 (baseline 스냅샷 복원)
if [[ "${SKIP_RESET:-0}" != "1" ]]; then
  echo "[$ITER] reset: restoring baseline snapshot..."
  bash "$CLUSTER_DIR/reset.sh" >/dev/null 2>&1
  echo "[$ITER] reset done. waiting for pods to settle..."
  _t=0
  until [ -z "$(kubectl --context $CTX get pods -A --no-headers 2>/dev/null | grep -vE 'Running|Completed')" ] \
        && kubectl --context $CTX get nodes --no-headers 2>/dev/null | grep -q Ready; do
    sleep 10; _t=$((_t+10))
    if [ "$_t" -ge 600 ]; then echo "[$ITER] ERROR: cluster not healthy after 600s" >&2; exit 1; fi
  done
  echo "[$ITER] cluster healthy (t+${_t}s)"
fi

# 2) 시나리오 적응(컨텍스트명 치환) + 고장 주입
bash "$HERE/adapt_scenario.sh" "$SCENARIO" "$OUT_DIR/scenario"
echo "[$ITER] setup: injecting scenario state..."
bash "$OUT_DIR/scenario/setup.sh" > "$OUT_DIR/setup.log" 2>&1
echo "[$ITER] setup done."

# 3) 작업 디렉토리 시딩 (콜드 스타트: 삭제 후 variant 복사, -a로 심링크 보존)
rm -rf "$WORK"; mkdir -p "$WORK"
cp -a "$VARIANTS/." "$WORK/"

# 4) 에이전트 실행 (OAuth 직접 호출: BASE_URL/AUTH_TOKEN unset)
PROMPT="$(cat "$OUT_DIR/scenario/PROMPT.md")"
echo "[$ITER] agent: running claude..."
AGENT_START_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
START_NS=$(gdate +%s%N 2>/dev/null || date +%s%N)

(cd "$WORK" && env -u ANTHROPIC_BASE_URL -u ANTHROPIC_AUTH_TOKEN \
  gtimeout "$TIMEOUT" \
  claude -p "$PROMPT" \
    --model "$MODEL" \
    --output-format stream-json \
    --verbose \
    --dangerously-skip-permissions) \
  > "$OUT_DIR/raw.json" \
  2> "$OUT_DIR/transcript.log"
AGENT_RC=$?

END_NS=$(gdate +%s%N 2>/dev/null || date +%s%N)
AGENT_END_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
WALL_MS=$(( (END_NS - START_NS) / 1000000 ))

# 5) timing.json (collect.py 호환) + meta.json (조건 기록)
echo "{\"wall_time_ms\": $WALL_MS, \"start_iso\": \"$AGENT_START_ISO\", \"end_iso\": \"$AGENT_END_ISO\"}" > "$OUT_DIR/timing.json"
_CLAUDE_V=$(claude --version 2>/dev/null | head -1)
echo "{\"cond\": \"$COND\", \"scenario\": \"$SCENARIO\", \"tag\": \"$TAG\", \"model\": \"$MODEL\", \"agent_rc\": $AGENT_RC, \"claude_version\": \"$_CLAUDE_V\", \"context\": \"$CTX\"}" > "$OUT_DIR/meta.json"

# 6) audit 슬라이스 캡처 (심링크 shim이 이 연구의 test-cluster를 가리킴, 비치명적)
bash "$ROOT/scripts/capture_audit.sh" "$OUT_DIR" "$AGENT_START_ISO" "$AGENT_END_ISO" >/dev/null 2>&1 || true

echo "[$ITER] === done in ${WALL_MS}ms (rc=$AGENT_RC) ==="
