#!/usr/bin/env bash
# 본 캠페인 실행 래퍼. 터미널/Claude 세션이 끝나도 살아남게 nohup + disown.
# 전원 관련: idle 슬립은 caffeinate, 뚜껑 닫힘은 clamshell-on-ac LaunchDaemon이 담당.
#
# 사용: ./launch_campaign.sh [days]   (기본 9일 마감)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAYS="${1:-9}"
STAMP="$(date +%Y%m%d-%H%M)"
OUT="$DIR/../runs/main-$STAMP"
DEADLINE=$(( $(date +%s) + DAYS*24*3600 ))
mkdir -p "$OUT"

# 사전 점검
command -v kubectl >/dev/null || { echo "kubectl 없음"; exit 1; }
kubectl --context cni-benchmark get nodes >/dev/null 2>&1 || {
  echo "클러스터 응답 없음. test-cluster를 먼저 올릴 것"; exit 1; }
pmset -g 2>/dev/null | grep -qi "sleepdisabled.*1" \
  || echo "WARN: SleepDisabled=1 아님. AC 연결 후 clamshell-on-ac 동작 확인 필요"

nohup caffeinate -i "$DIR/run_campaign.sh" "$OUT" "$DEADLINE" \
  > "$OUT/campaign.log" 2>&1 &
CAMPAIGN_PID=$!
disown "$CAMPAIGN_PID"
echo "$CAMPAIGN_PID" > "$OUT/campaign.pid"

echo "캠페인 시작됨."
echo "  PID:      $CAMPAIGN_PID"
echo "  출력:     $OUT"
echo "  마감:     $(date -r $DEADLINE '+%m-%d %H:%M')"
echo "  진행 확인: tail -f $OUT/progress.log"
echo "  중지:     kill \$(cat $OUT/campaign.pid)"
