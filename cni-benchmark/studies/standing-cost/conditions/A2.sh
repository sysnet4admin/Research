#!/usr/bin/env bash
# A2: A1 + FlowExporter on (Antrea 관측 비용, X2와 대칭 축)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP=$(mktemp)
# FlowExporter는 2단계: (1) FeatureGate (기본 false, 주석) (2) 목적지 flowExporter.enable.
# 본 캠페인 A2는 (2)만 켜서 무효였음(2026-08-03 발견). (1)을 주석 해제하며 true로:
#   '    #  FlowExporter: false' -> '      FlowExporter: true' (agent conf 유일 발생)
# (2)는 기존 awk 유지. flow-aggregator는 배치하지 않음 = 단일 변수 유지,
# 측정 대상은 export 기능 자체의 상시 비용(conntrack 폴링 + 전송 시도).
sed 's/^    #  FlowExporter: false$/      FlowExporter: true/' \
  "$VENDOR_DIR/antrea-$ANTREA_VER.yml" | awk '
  /flowExporter:/ { inFE=1; print; next }
  inFE && /enable:/ { sub(/enable: false/, "enable: true"); inFE=0; print; next }
  { print }
' > "$TMP"

# 적용 검증: 두 토글이 실제로 바뀌었는지 (안 바뀌면 조건 실패로 중단)
grep -q '^      FlowExporter: true$' "$TMP" || { echo "A2: FeatureGate 치환 실패"; exit 1; }
grep -q 'enable: true' "$TMP" || { echo "A2: flowExporter.enable 치환 실패"; exit 1; }

k apply -f "$TMP"
rm -f "$TMP"

wait_ds_ready kube-system antrea-agent 600
wait_nodes_ready 600
smoke_test
echo "A2 ready"
