#!/usr/bin/env bash
# 튜토리얼 재현 검증 (2026-08-18 분리). 발행문이 재현 가능하다고 주장하므로
# 문서에 적은 순서 그대로 돌려 보고, **각 단계의 성공 여부를 실제로 본다.**
#
# 왜 분리했나: 8/10 무인 실행에서 이 절차를 3부 스크립트 안에 인라인으로 넣고
# 세 단계를 `{ ... } > log` 블록으로 묶었다. 앞 단계 실패를 검사하지 않아서
# 이미지 빌드가 실패했는데도 배포로 넘어갔고, 이미지 없는 파드가 안 뜬 채로
# 뒤 캠페인 두 개가 그 위에서 돌았다. 재현 검증이 실패를 놓치면 검증이 아니다.
#
# 사용: ./verify_repro.sh <A_URL> <B_URL> <PYTHON> <OUT_DIR>
set -uo pipefail

A_URL="$1"; B_URL="$2"; PY="$3"; OUT="$4"
CTX="mcp-migration"; NS="mcp-pilot"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
TC="$(cd "$STUDY/../../test-cluster" && pwd)"
mkdir -p "$OUT"

FAILED=0
step() { # step <번호> <설명> <명령...>
  local n="$1" desc="$2"; shift 2
  echo "== $n. $desc ==" | tee -a "$OUT/repro.log"
  if "$@" >> "$OUT/repro.log" 2>&1; then
    echo "   [통과] $desc" | tee -a "$OUT/repro.log"
    return 0
  fi
  echo "   [실패] $desc (종료 코드 $?)" | tee -a "$OUT/repro.log"
  FAILED=1
  return 1
}

: > "$OUT/repro.log"
echo "재현 검증 시작 $(date '+%Y-%m-%d %H:%M')" | tee -a "$OUT/repro.log"

# 문서에 적은 순서: 기동 -> 스냅샷 복원 -> 이미지 빌드/적재 -> 배포
step 1 "스냅샷 복원" bash "$TC/reset.sh" || {
  echo "[중단] 스냅샷 복원이 실패하면 뒤를 볼 의미가 없다" | tee -a "$OUT/repro.log"
  exit 1
}
step 2 "이미지 빌드와 적재" bash "$STUDY/images/build_and_load.sh" || {
  echo "[중단] 이미지가 없으면 배포해도 파드가 뜨지 않는다." | tee -a "$OUT/repro.log"
  echo "       8/10 실행이 여기서 실패했는데 그대로 배포로 넘어가 문제를 키웠다." | tee -a "$OUT/repro.log"
  exit 1
}
step 3 "배포" bash "$STUDY/k8s/deploy.sh" || {
  echo "[중단] 배포 실패" | tee -a "$OUT/repro.log"
  exit 1
}

# 파드가 실제로 떴는지 본다. deploy.sh 의 rollout 대기가 타임아웃해도
# 종료 코드를 안 낼 수 있으므로 여기서 다시 확인한다.
echo "== 4. 파드 기동 확인 ==" | tee -a "$OUT/repro.log"
for d in mcp-a mcp-b redis; do
  R=$(kubectl --context $CTX -n $NS get deploy "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
  W=$(kubectl --context $CTX -n $NS get deploy "$d" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "?")
  if [ "${R:-0}" = "$W" ] && [ "${R:-0}" != "0" ]; then
    echo "   [통과] $d $R/$W" | tee -a "$OUT/repro.log"
  else
    echo "   [실패] $d ${R:-0}/$W" | tee -a "$OUT/repro.log"
    kubectl --context $CTX -n $NS get pod -l app="$d" \
      -o jsonpath='{range .items[*]}{.status.containerStatuses[0].state}{"\n"}{end}' >> "$OUT/repro.log" 2>&1
    FAILED=1
  fi
done

# 문서가 안내하는 최소 클라이언트가 실제로 도는지
echo "== 5. 최소 클라이언트 =="| tee -a "$OUT/repro.log"
for spec in old:$A_URL new:$B_URL; do
  mode="${spec%%:*}"; url="${spec#*:}"
  if OUTPUT=$("$PY" "$STUDY/examples/minimal_client.py" "$mode" "$url" 2>&1); then
    echo "   [통과] $mode -> $OUTPUT" | tee -a "$OUT/repro.log"
  else
    echo "   [실패] $mode -> $OUTPUT" | tee -a "$OUT/repro.log"
    FAILED=1
  fi
done

# 문서가 안내하는 캡처가 실제로 되는지 (양쪽 replica 2 필요)
echo "== 6. 페이로드 캡처 ==" | tee -a "$OUT/repro.log"
kubectl --context $CTX -n $NS scale deploy/mcp-a deploy/mcp-b --replicas=2 >/dev/null 2>&1
kubectl --context $CTX -n $NS rollout status deploy/mcp-b --timeout=180s >> "$OUT/repro.log" 2>&1
if "$PY" "$DIR/capture.py" "$A_URL" "$B_URL" "$OUT/payloads" >> "$OUT/repro.log" 2>&1; then
  N=$(python3 -c "import json;print(len(json.load(open('$OUT/payloads/payloads.json'))['records']))" 2>/dev/null || echo 0)
  echo "   [통과] 캡처 ${N}건" | tee -a "$OUT/repro.log"
else
  echo "   [실패] 캡처" | tee -a "$OUT/repro.log"
  FAILED=1
fi

echo | tee -a "$OUT/repro.log"
if [ "$FAILED" = "0" ]; then
  echo "재현 검증 통과. 발행문에 적은 순서대로 처음부터 다시 세울 수 있다." | tee -a "$OUT/repro.log"
else
  echo "재현 검증 실패. 위 [실패] 항목을 보고 발행문이나 스크립트를 고친다." | tee -a "$OUT/repro.log"
fi
exit "$FAILED"
