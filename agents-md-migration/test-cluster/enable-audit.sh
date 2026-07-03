#!/usr/bin/env bash
# enable-audit.sh - cp-k8s에서 실행. kube-apiserver에 audit 로깅을 켠다(멱등).
#   결정론 safety 캡처용. audit-policy.yaml을 /tmp/audit-policy.yaml로 먼저 업로드해 둘 것.
# 적용 후 재스냅샷(snapshot.sh baseline)하면 베이스라인에 영구 포함된다.
set -euo pipefail

POLICY_SRC="${1:-/tmp/audit-policy.yaml}"
MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"
AUDIT_DIR="/var/log/kubernetes/audit"

echo "==> audit 디렉토리 + 정책 배치"
sudo mkdir -p "$AUDIT_DIR"
sudo cp "$POLICY_SRC" /etc/kubernetes/audit-policy.yaml

echo "==> pyyaml 확인"
if ! python3 -c "import yaml" 2>/dev/null; then
  sudo apt-get install -y python3-yaml >/dev/null 2>&1 || sudo pip3 install pyyaml >/dev/null 2>&1
fi

echo "==> 매니페스트 백업 (static pod 디렉토리 밖 - kubelet이 .bak도 읽어 충돌하는 것 방지)"
sudo mkdir -p /etc/kubernetes/manifests-backup
sudo cp "$MANIFEST" "/etc/kubernetes/manifests-backup/kube-apiserver.yaml.bak.$(date +%s)"

echo "==> 매니페스트 패치(멱등)"
sudo python3 - "$MANIFEST" <<'PY'
import sys, yaml
p = sys.argv[1]
d = yaml.safe_load(open(p))
c = d["spec"]["containers"][0]
cmd = c["command"]
flags = [
    "--audit-policy-file=/etc/kubernetes/audit-policy.yaml",
    "--audit-log-path=/var/log/kubernetes/audit/audit.log",
    "--audit-log-maxsize=100",
    "--audit-log-maxbackup=3",
]
for f in flags:
    key = f.split("=")[0]
    if not any(str(x).startswith(key) for x in cmd):
        cmd.append(f)

vm = c.setdefault("volumeMounts", [])
def has_m(n): return any(m.get("name") == n for m in vm)
if not has_m("audit-policy"):
    vm.append({"name": "audit-policy", "mountPath": "/etc/kubernetes/audit-policy.yaml", "readOnly": True})
if not has_m("audit-log"):
    vm.append({"name": "audit-log", "mountPath": "/var/log/kubernetes/audit", "readOnly": False})

vols = d["spec"].setdefault("volumes", [])
def has_v(n): return any(v.get("name") == n for v in vols)
if not has_v("audit-policy"):
    vols.append({"name": "audit-policy", "hostPath": {"path": "/etc/kubernetes/audit-policy.yaml", "type": "File"}})
if not has_v("audit-log"):
    vols.append({"name": "audit-log", "hostPath": {"path": "/var/log/kubernetes/audit", "type": "DirectoryOrCreate"}})

yaml.safe_dump(d, open(p, "w"), default_flow_style=False, sort_keys=False)
print("  patched command/volumeMounts/volumes")
PY

echo "==> kubelet이 apiserver 재기동(최대 120s 대기)"
for i in $(seq 1 24); do
  if sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get --raw='/healthz' >/dev/null 2>&1; then
    echo "  apiserver healthy (t+$((i*5))s)"; break
  fi
  sleep 5
done

echo "==> audit.log 생성 확인"
sleep 3
sudo ls -la "$AUDIT_DIR"/audit.log 2>&1 || echo "  아직 audit.log 없음(요청 발생 후 생성됨)"
echo "==> 완료"
