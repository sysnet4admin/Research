#!/usr/bin/env bash
# A1: Antrea 기본 (Geneve, OVS 데몬, kube-proxy 유지, FlowExporter off)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

k apply -f "$VENDOR_DIR/antrea-$ANTREA_VER.yml"

wait_ds_ready kube-system antrea-agent 600
wait_nodes_ready 600
smoke_test
echo "A1 ready"
