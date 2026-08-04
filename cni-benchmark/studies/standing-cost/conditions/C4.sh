#!/usr/bin/env bash
# C4: C1 + BGP on (BIRD 상주 비용 분리)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

install_calico_operator
apply_calico_cr "$COND_DIR/cr/calico-c4.yaml"

wait_ds_ready calico-system calico-node 600
wait_nodes_ready 600
smoke_test
echo "C4 ready"
