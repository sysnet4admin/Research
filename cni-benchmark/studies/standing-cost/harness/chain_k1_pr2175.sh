#!/usr/bin/env bash
# PR #2175(aauren, kube-router 메인테이너) 검증 체인 (2026-09-28). 메인테이너가 #2165 에서
# 직접 테스트를 요청했다. PR 이 갈라진 master 지점(9d175a71, 스톡)과 PR 본(00d9a0aa)을
# 9/22 야간과 같은 절차(k1_fixtest.sh, v2.11.1 매니페스트 위에 바이너리 교체)로 잰다.
# 2회차 약 2시간 30분. 완주하면 요약을 남기고 VM 을 내린다.
#
# chain_k1_night.sh 의 최소 델타 사본이다. 다른 점: 창 대기 없음, 바이너리 경로가
# /tmp 밖(~/.cache/cni-benchmark/bins), 클러스터 사전 접근 검사 없음(k1_fixtest 가 스냅샷
# 복원부터 하므로 VM 이 꺼져 있어도 된다). 수치 발행 금지, 업스트림 답글 근거용.
#
# 기동: caffeinate -i nohup ./harness/chain_k1_pr2175.sh > /tmp/chain-k1-pr2175.log 2>&1 & disown
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(cd "$DIR/.." && pwd)"
CLUSTER="$STUDY/../../test-cluster"
BINS=$HOME/.cache/cni-benchmark/bins
say() { echo "[chain $(date '+%m-%d %H:%M:%S')] $*"; }

# ---- 전제검사 ----
for b in k1-pr2175base k1-pr2175; do
  [ -x "$BINS/$b" ] || { say "중단: 바이너리 없음 $BINS/$b"; exit 1; }
done
[ -f "$STUDY/vendor/kuberouter-all-v2.11.1.yaml" ] \
  || { say "중단: v2.11.1 manifest 없음"; exit 1; }
say "전제검사 통과"
while pgrep -f "k1_pprof.sh|k1_fixtest.sh|k1_recovery.sh|run_campaign.sh" >/dev/null; do
  say "앞선 런 진행 중. 5분 뒤 다시 본다"; sleep 300
done
say "회차 시작"

cd "$STUDY"

run_one() { # run_one <이름> <OUT> <명령...>
  local name="$1" out="$2"; shift 2
  if [ -f "$out/progress.log" ] && grep -q "^\[.*\] 완료:" "$out/progress.log"; then
    say "$name 이미 완료. 건너뛴다"; return 0
  fi
  say "$name 시작 -> $out"
  "$@" >>"/tmp/chain-k1-pr2175-$name.log" 2>&1
  local rc=$?
  say "$name 끝 (종료코드 $rc)"
  sleep 180
  return 0
}

V=v2.11.1
run_one pr2175-base runs/k1-pr2175base-0928 \
  env KUBEROUTER_VER=$V ./harness/k1_fixtest.sh runs/k1-pr2175base-0928 "$BINS/k1-pr2175base"
run_one pr2175      runs/k1-pr2175-0928 \
  env KUBEROUTER_VER=$V ./harness/k1_fixtest.sh runs/k1-pr2175-0928 "$BINS/k1-pr2175"

say "PR 2175 검증 완료 (2회차)"

# ---- 완주 검사 -> 요약 -> VM 종료 ----
# 증거는 전부 호스트의 runs/ 에 있으므로 VM 을 내려도 잃지 않는다. 다만 한 회차라도
# 미완이면 이어서 돌리거나 원인을 봐야 하므로 켜 둔다.
DIRS="runs/k1-pr2175base-0928 runs/k1-pr2175-0928"
SUM="runs/k1-pr2175-0928-SUMMARY.txt"
ok=1
: > "$SUM"
{
  echo "PR 2175 검증 요약 ($(date '+%Y-%m-%d %H:%M'))"
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
  say "2회차 완주 확인. 요약: $SUM"
  say "VM 종료"
  ( cd "$CLUSTER" && vagrant halt ) >>/tmp/chain-k1-pr2175-halt.log 2>&1 \
    && say "VM 종료 완료. 리소스 반환됨" \
    || say "ERROR: vagrant halt 실패. /tmp/chain-k1-pr2175-halt.log 확인"
else
  say "미완 회차가 있어 VM 을 켜 둔다. 같은 명령을 다시 걸면 남은 것만 돈다"
fi
