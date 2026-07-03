#!/usr/bin/env bash
# adapt_scenario.sh: AIOps 시나리오 원본을 매 실행 시점에 이 클러스터용으로 치환한다.
#
# AIOps setup.sh/PROMPT.md는 컨텍스트명 "AIOps-Agent-Benchmark"가 박혀 있다. 이 연구는
# 전용 클러스터를 쓰므로 컨텍스트명도 "agents-md-migration"으로 실제로 바뀌어야 한다.
# 원본을 복제해 두지 않고, 실행할 때마다 원본에서 다시 만든다(drift 없음).
#
# Usage: ./adapt_scenario.sh <scenario-slug> <output-dir>
# 결과: <output-dir>/setup.sh, <output-dir>/PROMPT.md (컨텍스트명만 치환, 그 외 내용은 원본 그대로)

set -euo pipefail

SLUG="${1:?Usage: $0 <scenario-slug> <output-dir>}"
OUT_DIR="${2:?Usage: $0 <scenario-slug> <output-dir>}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AIOPS_SCENARIOS="$HERE/../../../AIOps-Agent-Benchmark/scenarios"
SRC_DIR="$AIOPS_SCENARIOS/$SLUG"

OLD_CTX="AIOps-Agent-Benchmark"
NEW_CTX="agents-md-migration"

if [[ ! -d "$SRC_DIR" ]]; then
  echo "Error: $SRC_DIR not found" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
sed "s/$OLD_CTX/$NEW_CTX/g" "$SRC_DIR/setup.sh" > "$OUT_DIR/setup.sh"
chmod +x "$OUT_DIR/setup.sh"
sed "s/$OLD_CTX/$NEW_CTX/g" "$SRC_DIR/PROMPT.md" > "$OUT_DIR/PROMPT.md"

echo "adapted $SLUG -> $OUT_DIR (context: $OLD_CTX -> $NEW_CTX)"
