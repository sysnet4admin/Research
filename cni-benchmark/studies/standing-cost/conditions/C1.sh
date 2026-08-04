#!/usr/bin/env bash
# C1: Calico operator 설치, iptables 데이터플레인, VXLAN, BGP off
# (BGP off 사유: C3(manifest, vxlan backend=BIRD 없음)과 operator 계층만 차이 나게 통제.
#  BIRD 상주 비용은 C4(=C1+BGP on)가 분리 측정)
# 방식: operator 매니페스트(CRD 런타임 생성) -> Installation CR 적용
# (helm 차트는 CRD 미포함이라 helm 한 번에 CR 생성 시도하면 실패, 리허설에서 실측)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

install_calico_operator
apply_calico_cr "$COND_DIR/cr/calico-c1.yaml"

wait_ds_ready calico-system calico-node 600
wait_nodes_ready 600
smoke_test
echo "C1 ready"
