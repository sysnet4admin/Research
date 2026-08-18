#!/usr/bin/env bash
# 7/28 릴리즈 당일 사전 점검: 스펙 확정판과 SDK 안정판이 실제로 나왔는지,
# 파일럿 때와 달라진 것이 있는지 확인한다. 전부 읽기 전용 (변경 없음).
# 사용: ./release_check.sh
set -uo pipefail

echo "======================================================"
echo " MCP 2026-07-28 릴리즈 사전 점검 ($(date +%F))"
echo "======================================================"

echo ""
echo "## 1. 스펙 확정판 발행 여부"
SPEC=$(curl -s -o /dev/null -w "%{http_code}" https://modelcontextprotocol.io/specification/2026-07-28/changelog)
if [ "$SPEC" = "200" ]; then
  echo "  [OK] https://modelcontextprotocol.io/specification/2026-07-28 발행됨"
else
  echo "  [대기] 2026-07-28 스펙 URL 아직 없음 (HTTP $SPEC). draft로 남아 있으면 연기된 것"
fi

echo ""
echo "## 2. Python SDK 안정판 (mcp 2.0.0)"
PY_LATEST=$(curl -s https://pypi.org/pypi/mcp/json | python3 -c "import json,sys; print(json.load(sys.stdin)['info']['version'])" 2>/dev/null)
echo "  PyPI mcp 최신: ${PY_LATEST:-조회 실패}  (파일럿은 2.0.0b1)"
case "$PY_LATEST" in
  2.0.0) echo "  [OK] 안정판. build_and_load.sh 2.0.0 로 이미지 재빌드" ;;
  2.*b*|2.*rc*) echo "  [대기] 아직 프리릴리즈" ;;
  *) echo "  [확인 필요] 예상 밖 버전" ;;
esac

echo ""
echo "## 3. TypeScript SDK 안정판"
TS_LATEST=$(npm view @modelcontextprotocol/server version 2>/dev/null)
echo "  npm @modelcontextprotocol/server latest: ${TS_LATEST:-조회 실패}  (파일럿은 2.0.0-beta.2)"

echo ""
echo "## 4. everything 서버 (A쪽은 v1 세션 기반 유지가 전제)"
EV_LATEST=$(npm view @modelcontextprotocol/server-everything version 2>/dev/null)
echo "  npm server-everything latest: ${EV_LATEST:-조회 실패}  (A쪽 고정 핀: 2026.7.4)"
echo "  [주의] PR #4452(v2 이관) 병합 여부 확인: latest가 v2 기반이 되어도 A쪽은 2026.7.4 유지"

echo ""
echo "## 5. agentgateway 신 스펙 지원 (경로 c)"
AGW=$(gh api repos/agentgateway/agentgateway/releases --jq '.[0:3][] | .tag_name + "  " + .published_at' 2>/dev/null)
echo "${AGW:-  조회 실패}" | sed 's/^/  /'
echo "  [기준] v1.4.0-alpha.1은 신 스펙 end-to-end 불가(_meta 훼손, 2026-07-08 실측)."
echo "         이후 릴리즈에서 재검증: curl로 /b에 신 스펙 tools/call 1건"

echo ""
echo "## 6. RC 대비 델타 확인 (수동)"
echo "  changelog 다시 읽기: https://modelcontextprotocol.io/specification/2026-07-28/changelog"
echo "  파일럿 하네스가 의존하는 것: _meta 3키 이름, Mcp-Method/Mcp-Name 헤더, 404/400 시맨틱"
echo ""
echo "점검 끝. 모두 OK면 RELEASE_DAY.md 순서대로 진행."
