#!/usr/bin/env bash
# 야간 무인 창(2026-09-22 18:00~): kube-router K1 히스테리시스를 최신 릴리스와
# 개발 브랜치에서 재현한다. 4회차 약 4시간이고 22시 무렵 끝난다.
#
# 완주하면 요약을 남기고 vagrant halt 로 VM 을 내린다(2026-09-22 저자 요청).
# 다른 연구가 M4 를 쓸 수 있게 리소스를 돌려준다. 한 회차라도 미완이면 켜 둔다.
#
# 자연 회복 관찰(k1_recovery.sh)은 저자 결정으로 뺐다(2026-09-22). 남는 시간을
# 다른 작업에 쓴다. 회복 시간을 주장할 일이 생기면 그때 한 회차 더 돌린다.
#
# chain_a2a_weekend.sh의 최소 델타 사본이다(전제검사, 체크포인트 건너뛰기,
# 회차 간 대기를 그대로 따른다). 측정용 아님(수치 발행 금지, 제보 증거용).
#
# 기동: caffeinate -i nohup ./harness/chain_k1_night.sh > /tmp/chain-k1.log 2>&1 & disown
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
CLUSTER="$STUDY/../../test-cluster"
BINS=/tmp/k1bins
START_HOUR=${START_HOUR:-18}
say() { echo "[chain $(date '+%m-%d %H:%M:%S')] $*"; }

# ---- 전제검사 ----
kubectl --context cni-benchmark get nodes >/dev/null 2>&1 \
  || { say "중단: 클러스터 접근 불가"; exit 1; }
for b in k1-v2111-fix k1-master-stock k1-master-fix; do
  [ -x "$BINS/$b" ] || { say "중단: 바이너리 없음 $BINS/$b"; exit 1; }
done
[ -f "$STUDY/vendor/kuberouter-all-v2.11.1.yaml" ] \
  || { say "중단: v2.11.1 manifest 없음"; exit 1; }
say "전제검사 통과"

# ---- 앞선 런이 끝날 때까지, 그리고 창이 열릴 때까지 기다린다 ----
while pgrep -f "k1_pprof.sh|k1_fixtest.sh|k1_recovery.sh" >/dev/null; do
  say "앞선 런 진행 중. 5분 뒤 다시 본다"; sleep 300
done
while [ "$(date +%-H)" -lt "$START_HOUR" ]; do
  say "창 대기(${START_HOUR}시 시작). 10분 뒤 다시 본다"; sleep 600
done
say "창 열림. 회차 시작"

cd "$STUDY"

run_one() { # run_one <이름> <OUT> <명령...>
  local name="$1" out="$2"; shift 2
  if [ -f "$out/progress.log" ] && grep -q "^\[.*\] 완료:" "$out/progress.log"; then
    say "$name 이미 완료. 건너뛴다"; return 0
  fi
  say "$name 시작 -> $out"
  "$@" >>"/tmp/chain-k1-$name.log" 2>&1
  local rc=$?
  say "$name 끝 (종료코드 $rc)"
  sleep 180
  return 0
}

V=v2.11.1
run_one v2111-stock   runs/k1-v2111-stock-0922 \
  env KUBEROUTER_VER=$V ./harness/k1_pprof.sh runs/k1-v2111-stock-0922
run_one v2111-fix     runs/k1-v2111-fix-0922 \
  env KUBEROUTER_VER=$V ./harness/k1_fixtest.sh runs/k1-v2111-fix-0922 "$BINS/k1-v2111-fix"
run_one master-stock  runs/k1-master-stock-0922 \
  env KUBEROUTER_VER=$V ./harness/k1_fixtest.sh runs/k1-master-stock-0922 "$BINS/k1-master-stock"
run_one master-fix    runs/k1-master-fix-0922 \
  env KUBEROUTER_VER=$V ./harness/k1_fixtest.sh runs/k1-master-fix-0922 "$BINS/k1-master-fix"

say "야간 창 완료 (4회차)"

# ---- 완주 검사 -> 요약 -> VM 종료 ----
# 증거는 전부 호스트의 runs/ 에 있으므로 VM 을 내려도 잃지 않는다. 다만 한 회차라도
# 미완이면 이어서 돌리거나 원인을 봐야 하므로 켜 둔다.
DIRS="runs/k1-v2111-stock-0922 runs/k1-v2111-fix-0922 runs/k1-master-stock-0922 runs/k1-master-fix-0922"
SUM="runs/k1-night-0922-SUMMARY.txt"
ok=1
: > "$SUM"
{
  echo "야간 4회차 요약 ($(date '+%Y-%m-%d %H:%M'))"
  echo "수치 발행 금지. 업스트림 제보 증거용이다."
  echo
} >> "$SUM"

export PATH="$PATH:/usr/local/go/bin:/opt/homebrew/bin"
for d in $DIRS; do
  if [ ! -f "$d/progress.log" ] || ! grep -q "완료:" "$d/progress.log"; then
    say "미완: $d"; echo "[미완] $d" >> "$SUM"; ok=0; continue
  fi
  n=$(ls "$d"/profile-*.pb.gz 2>/dev/null | wc -l | tr -d " ")
  if [ "${n:-0}" -lt 3 ]; then
    say "프로파일 부족: $d ($n개)"; echo "[부족] $d 프로파일 ${n}개" >> "$SUM"; ok=0; continue
  fi
  echo "== $d" >> "$SUM"
  for f in "$d"/profile-*.pb.gz; do
    tot=$(go tool pprof -top "$f" 2>/dev/null | grep -oE "Total samples = .*" | sed "s/Total samples = //")
    printf "   %-28s %8s B  %s\n" "$(basename "$f" .pb.gz | sed "s/profile-//")" "$(stat -f%z "$f")" "${tot:-(go 없음)}" >> "$SUM"
  done
  echo >> "$SUM"
done

if [ "$ok" = 1 ]; then
  say "4회차 완주 확인. 요약: $SUM"
  say "VM 종료"
  ( cd "$CLUSTER" && vagrant halt ) >>/tmp/chain-k1-halt.log 2>&1 \
    && say "VM 종료 완료. 리소스 반환됨" \
    || say "ERROR: vagrant halt 실패. /tmp/chain-k1-halt.log 확인"
else
  say "미완 회차가 있어 VM 을 켜 둔다. 같은 명령을 다시 걸면 남은 것만 돈다"
fi
