#!/usr/bin/env bash
# import-kubeconfig.sh — CP 노드의 admin.conf 를 호스트 kubeconfig 에 병합한다.
#
# README 가 이 절차를 문서로만 가리키고 실제 명령이 없어 매번 손으로 했다.
# 클러스터 이름·사용자 이름까지 바꿔야 여러 클러스터가 한 kubeconfig 에 공존한다.
#
# 사용: ./import-kubeconfig.sh
#       CLUSTER_SUFFIX=yozm K8S_VERSION=1.37.0-1.1 ./import-kubeconfig.sh
set -euo pipefail
source "$(dirname "$0")/config.sh"
cd "$CLUSTER_DIR"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
echo "==> $CP_VM 에서 admin.conf 가져오기"
vagrant ssh "$CP_VM" -c "sudo cat /etc/kubernetes/admin.conf" 2>/dev/null > "$TMP/admin.conf"
[[ -s "$TMP/admin.conf" ]] || { echo "admin.conf 를 못 가져왔다"; exit 1; }

NAME="$KUBE_CONTEXT"
kubectl --kubeconfig "$TMP/admin.conf" config rename-context kubernetes-admin@kubernetes "$NAME" >/dev/null
# cluster 와 user 키도 바꾼다. 기본 이름(kubernetes, kubernetes-admin)은 모든
# kubeadm 클러스터가 같아서 그대로 병합하면 먼저 있던 항목을 덮어쓴다.
python3 - "$TMP/admin.conf" "$NAME" <<'PY'
import sys, yaml
p, name = sys.argv[1], sys.argv[2]
d = yaml.safe_load(open(p))
for c in d["clusters"]: c["name"] = name
for u in d["users"]:    u["name"] = f"{name}-admin"
for c in d["contexts"]:
    c["context"]["cluster"] = name
    c["context"]["user"] = f"{name}-admin"
yaml.safe_dump(d, open(p, "w"))
PY

echo "==> ~/.kube/config 에 병합"
cp ~/.kube/config "$HOME/.kube/config.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
KUBECONFIG="$HOME/.kube/config:$TMP/admin.conf" kubectl config view --flatten > "$TMP/merged"
mv "$TMP/merged" "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"

echo "==> 확인"
kubectl --context "$NAME" get nodes
echo "컨텍스트: $NAME"
