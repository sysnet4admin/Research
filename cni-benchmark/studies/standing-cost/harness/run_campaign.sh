#!/usr/bin/env bash
# 무인 캠페인 러너 (9일 설계).
#
# 구조: 반복(rep) 루프 > 조건 루프 > [스냅샷 복원 -> 조건 설치 -> 안정화 ->
#       수집기 시작 -> 페이즈 6개 -> 수집기 종료 -> 저장]
#
# 방어 설계 (무인 중 고칠 사람이 없음):
# - 조건 하나가 실패해도 기록하고 다음 조건으로 진행
# - 실패 조건은 각 rep 말미에 1회 자동 재시도
# - 전 단계 타임아웃, 스냅샷 복원 실패 시 2회 재시도
# - 마감 시각(DEADLINE) 인지: 새 조건 시작 전에 남은 시간 확인, 부족하면 종료
# - rep 3 완료 후 시간이 남으면 rep 4 자동 (짧은 idle)
# - 진행 상황을 progress.log에 사람이 읽을 수 있게 기록
#
# 사용: ./run_campaign.sh <OUT_DIR> [DEADLINE_EPOCH]
#   DEADLINE 기본 = 시작 + 9일

set -uo pipefail   # -e 없음: 실패를 스스로 다루는 러너

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDY="$(dirname "$DIR")"
CLUSTER="$STUDY/../../test-cluster"
OUT="${1:?OUT_DIR 필요}"
DEADLINE="${2:-$(( $(date +%s) + 9*24*3600 ))}"
CTX="cni-benchmark"

CONDITIONS=(C1 C2 C3 C4 X1 X2 X3 X4 F1 F1n A1 A2 K1 K2)
# (CONDITIONS_OVERRIDE 반영은 아래 env 파싱 후)

# 페이즈 길이 (초). rep1은 긴 idle, rep2+는 짧은 idle. env로 재정의 가능(리허설용)
IDLE_LONG="${IDLE_LONG:-7200}"; IDLE_SHORT="${IDLE_SHORT:-3600}"
T_DENSITY="${T_DENSITY:-1800}"; T_POLICY="${T_POLICY:-1200}"
T_SERVICE="${T_SERVICE:-1800}"; T_CHURN="${T_CHURN:-1200}"; T_NODE="${T_NODE:-1200}"
STABILIZE="${STABILIZE:-1800}"   # 설치 후 안정화 (Cilium identity GC 15분 포함 여유)
# 조건 목록 env 재정의 (리허설: CONDITIONS_OVERRIDE="F1n K1" 등)
if [ -n "${CONDITIONS_OVERRIDE:-}" ]; then
  read -ra CONDITIONS <<< "$CONDITIONS_OVERRIDE"
fi
# 반복 횟수 상한 env 재정의 (리허설: MAX_REP=1)
MAX_REP="${MAX_REP:-4}"

mkdir -p "$OUT"
PROG="$OUT/progress.log"
log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" | tee -a "$PROG"; }

k() { kubectl --context "$CTX" "$@"; }

restore_base() {
  local try
  for try in 1 2 3; do
    log "  스냅샷 복원 (시도 $try)"
    ( cd "$CLUSTER" && vagrant snapshot restore base-no-cni ) >>"$OUT/vagrant.log" 2>&1
    sleep 30
    # API 응답 대기 (최대 5분)
    local start=$SECONDS
    while [ $((SECONDS - start)) -lt 300 ]; do
      k get nodes >/dev/null 2>&1 && return 0
      sleep 10
    done
  done
  return 1
}

run_condition() { # run_condition <ID> <rep> <idle_s>
  local id="$1" rep="$2" idle_s="$3"
  local cell="$OUT/rep$rep/$id"
  mkdir -p "$cell"
  local phase_file="$cell/phase.txt"
  echo "restore" > "$phase_file"

  log "[$id rep$rep] 시작"

  restore_base || { log "[$id rep$rep] FAIL: 스냅샷 복원 불가"; return 1; }

  echo "install" > "$phase_file"
  if ! timeout 1500 "$STUDY/conditions/$id.sh" >"$cell/install.log" 2>&1; then
    log "[$id rep$rep] FAIL: 조건 설치 (install.log 참조)"
    k get pods -A >"$cell/pods-at-failure.txt" 2>&1 || true
    return 1
  fi

  # 수집기 시작 (백그라운드)
  python3 "$DIR/collect.py" --out "$cell/metrics.jsonl" --interval 15 \
    --phase-file "$phase_file" --cluster-dir "$CLUSTER" &
  local COLLECTOR_PID=$!

  echo "stabilize" > "$phase_file"
  sleep "$STABILIZE"

  # 페이즈 실행 (각각 타임아웃)
  export PHASE_FILE="$phase_file"
  local failed=""
  timeout $((idle_s + 120)) bash "$DIR/phases.sh" idle "$idle_s"       || failed="idle"
  [ -z "$failed" ] && { timeout $((T_DENSITY + 600)) bash "$DIR/phases.sh" density "$T_DENSITY" || failed="density"; }
  [ -z "$failed" ] && { timeout $((T_POLICY + 600))  bash "$DIR/phases.sh" policy "$T_POLICY"   || failed="policy"; }
  [ -z "$failed" ] && { timeout $((T_SERVICE + 600)) bash "$DIR/phases.sh" service "$T_SERVICE" || failed="service"; }
  [ -z "$failed" ] && { timeout $((T_CHURN + 600))   bash "$DIR/phases.sh" churn "$T_CHURN"     || failed="churn"; }
  [ -z "$failed" ] && { timeout $((T_NODE + 600))    bash "$DIR/phases.sh" node "$T_NODE"       || failed="node"; }
  bash "$DIR/phases.sh" cleanup 60 >/dev/null 2>&1 || true

  # 수집기 종료
  kill "$COLLECTOR_PID" 2>/dev/null; wait "$COLLECTOR_PID" 2>/dev/null

  # 조건 메타 기록
  {
    echo "{\"condition\": \"$id\", \"rep\": $rep, \"idle_s\": $idle_s,"
    echo " \"failed_phase\": \"${failed:-none}\", \"finished\": \"$(date -u +%FT%TZ)\"}"
  } > "$cell/meta.json"

  if [ -n "$failed" ]; then
    log "[$id rep$rep] PARTIAL: $failed 페이즈 실패 (이전 페이즈 데이터는 유효)"
    return 2
  fi
  log "[$id rep$rep] 완료"
  return 0
}

time_left() { echo $(( DEADLINE - $(date +%s) )); }

# 조건 하나에 필요한 최대 시간 추정 (복원+설치+안정화+페이즈+여유)
need_s() { echo $(( 600 + 1500 + STABILIZE + $1 + T_DENSITY + T_POLICY + T_SERVICE + T_CHURN + T_NODE + 900 )); }

log "==== 캠페인 시작. 마감: $(date -r "$DEADLINE" '+%m-%d %H:%M') ===="
log "조건 ${#CONDITIONS[@]}개: ${CONDITIONS[*]}"

for rep in 1 2 3 4; do
  # rep4는 시간이 남을 때만
  idle_s=$IDLE_SHORT
  [ "$rep" = "1" ] && idle_s=$IDLE_LONG
  FAILED_CONDS=()

  for id in "${CONDITIONS[@]}"; do
    if [ "$(time_left)" -lt "$(need_s $idle_s)" ]; then
      log "==== 시간 부족, rep$rep 중단 (남은 $(( $(time_left)/3600 ))h) ===="
      break 2
    fi
    run_condition "$id" "$rep" "$idle_s"
    rc=$?
    [ "$rc" = "1" ] && FAILED_CONDS+=("$id")
  done

  # 실패 조건 재시도 (설치 실패만. 부분 실패는 데이터가 있으니 두 번째 rep에 맡김)
  if [ "${#FAILED_CONDS[@]}" -gt 0 ]; then
    log "rep$rep 재시도 대상: ${FAILED_CONDS[*]}"
    for id in "${FAILED_CONDS[@]}"; do
      [ "$(time_left)" -lt "$(need_s $idle_s)" ] && break
      log "[$id rep$rep] 재시도"
      run_condition "$id" "${rep}retry" "$idle_s"
    done
  fi

  log "==== rep$rep 종료. 남은 시간: $(( $(time_left)/3600 ))h ===="
  [ "$rep" -ge "$MAX_REP" ] && break
done

# 종료: 클러스터를 베이스로 복원해 두고 halt (돌아와서 검증 재현 가능하게)
restore_base >/dev/null 2>&1 || true
( cd "$CLUSTER" && vagrant halt ) >>"$OUT/vagrant.log" 2>&1 || true
log "==== 캠페인 종료 ===="
