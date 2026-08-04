#!/usr/bin/env bash
# 프리페치: 조건 14개의 manifest/helm 차트를 vendor/에 저장하고,
# 모든 컨테이너 이미지를 3개 노드의 containerd에 미리 적재한다.
# 목적: 무인 9일 동안 레지스트리 rate limit과 네트워크 장애 의존 제거.
# 베이스 스냅샷 직전에 1회 실행.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/conditions/lib.sh" 2>/dev/null || true
VENDOR="$DIR/vendor"
mkdir -p "$VENDOR"

CALICO_VER="v3.32.1"
CILIUM_VER="1.19.5"
FLANNEL_VER="v0.28.7"
ANTREA_VER="v2.6.2"
KUBEROUTER_VER="v2.10.0"

echo "## 1. manifest / 차트 다운로드"

fetch() { # fetch <url> <dest>
  local url="$1" dest="$2"
  [ -s "$dest" ] && { echo "  skip (있음): $(basename "$dest")"; return; }
  echo "  get: $url"
  curl -fsSL "$url" -o "$dest"
}

fetch "https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VER/manifests/calico.yaml" \
  "$VENDOR/calico-$CALICO_VER.yaml"
fetch "https://github.com/projectcalico/calico/releases/download/$CALICO_VER/tigera-operator-$CALICO_VER.tgz" \
  "$VENDOR/tigera-operator-$CALICO_VER.tgz"
fetch "https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VER/manifests/tigera-operator.yaml" \
  "$VENDOR/tigera-operator-manifest-$CALICO_VER.yaml"
fetch "https://raw.githubusercontent.com/flannel-io/flannel/$FLANNEL_VER/Documentation/kube-flannel.yml" \
  "$VENDOR/kube-flannel-$FLANNEL_VER.yml"
fetch "https://github.com/antrea-io/antrea/releases/download/$ANTREA_VER/antrea.yml" \
  "$VENDOR/antrea-$ANTREA_VER.yml"
fetch "https://raw.githubusercontent.com/cloudnativelabs/kube-router/$KUBEROUTER_VER/daemonset/kubeadm-kuberouter-all-features.yaml" \
  "$VENDOR/kuberouter-all-$KUBEROUTER_VER.yaml"
fetch "https://raw.githubusercontent.com/cloudnativelabs/kube-router/$KUBEROUTER_VER/daemonset/kubeadm-kuberouter.yaml" \
  "$VENDOR/kuberouter-cni-$KUBEROUTER_VER.yaml"

if [ ! -s "$VENDOR/cilium-$CILIUM_VER.tgz" ]; then
  helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
  helm repo update cilium >/dev/null
  helm pull cilium/cilium --version "$CILIUM_VER" -d "$VENDOR"
fi

echo "## 2. 이미지 목록 수집"

IMGS_FILE="$VENDOR/images.txt"
{
  # manifest 계열: image: 라인 추출
  grep -h "image:" \
    "$VENDOR/calico-$CALICO_VER.yaml" \
    "$VENDOR/kube-flannel-$FLANNEL_VER.yml" \
    "$VENDOR/antrea-$ANTREA_VER.yml" \
    "$VENDOR/kuberouter-all-$KUBEROUTER_VER.yaml" \
    "$VENDOR/kuberouter-cni-$KUBEROUTER_VER.yaml" \
    | sed 's/.*image: *//; s/"//g'

  # helm 계열: template 렌더 후 추출 (조건별 values 반영)
  helm template calico "$VENDOR/tigera-operator-$CALICO_VER.tgz" \
    -f "$DIR/conditions/values/calico-c1.yaml" 2>/dev/null | grep "image:" | sed 's/.*image: *//; s/"//g'
  helm template calico "$VENDOR/tigera-operator-$CALICO_VER.tgz" \
    -f "$DIR/conditions/values/calico-c2.yaml" 2>/dev/null | grep "image:" | sed 's/.*image: *//; s/"//g'
  helm template cilium "$VENDOR/cilium-$CILIUM_VER.tgz" \
    -f "$DIR/conditions/values/cilium-x1.yaml" 2>/dev/null | grep " image:" | sed 's/.*image: *//; s/"//g; s/@sha256.*//'
  helm template cilium "$VENDOR/cilium-$CILIUM_VER.tgz" \
    -f "$DIR/conditions/values/cilium-x1.yaml" \
    -f "$DIR/conditions/values/cilium-x3-extra.yaml" \
    --set hubble.enabled=false 2>/dev/null | grep " image:" | sed 's/.*image: *//; s/"//g; s/@sha256.*//'

  # 측정 워크로드 이미지 (스모크/페이즈 공용)
  echo "registry.k8s.io/e2e-test-images/agnhost:2.53"
  echo "registry.k8s.io/pause:3.10"
} | sort -u | grep -v "^$" \
  | awk '{ if ($0 !~ /^[^\/]*[.:]/) print "docker.io/" $0; else print }' \
  | awk -v kr="$KUBEROUTER_VER" '{ if ($0 ~ /kube-router$/) print $0 ":" kr; else print }' \
  > "$IMGS_FILE"   # 접두사 정규화 + kube-router 무태그(:latest 부동) -> 버전 고정

echo "  이미지 $(wc -l < "$IMGS_FILE" | tr -d ' ')개:"
sed 's/^/    /' "$IMGS_FILE"

echo "## 3. Calico operator 이미지 보강"
# tigera-operator가 런타임에 당기는 이미지는 매니페스트/템플릿에 안 나옴 -> 명시 추가.
# goldmane/whisker/csi 등 v3.32 신규 컴포넌트 포함.
{
  cat "$IMGS_FILE"
  grep "image:" "$VENDOR/tigera-operator-manifest-$CALICO_VER.yaml" | sed 's/.*image: *//; s/"//g'
  for img in node cni kube-controllers typha pod2daemon-flexvol csi node-driver-registrar \
             apiserver goldmane whisker whisker-backend envoy-gateway envoy-ratelimit envoy-proxy; do
    echo "docker.io/calico/$img:$CALICO_VER"
  done
} | sort -u > "$IMGS_FILE.tmp" && mv "$IMGS_FILE.tmp" "$IMGS_FILE"

echo "## 4. 노드 3개에 이미지 적재 (ctr pull)"
CLUSTER="$DIR/../../test-cluster"
for port in 60350 60351 60352; do
  vm="cp-k8s-1.36.2"; [ "$port" = "60351" ] && vm="w1-k8s-1.36.2"; [ "$port" = "60352" ] && vm="w2-k8s-1.36.2"
  KEY="$CLUSTER/.vagrant/machines/$vm/virtualbox/private_key"   # VM마다 키가 다름
  echo "  == $vm (port $port) =="
  while IFS= read -r img; do
    ok=false
    for try in 1 2 3; do
      # ssh -n 필수: 없으면 ssh가 stdin(이미지 목록)을 삼켜 루프가 1회로 끝남
      if ssh -n -i "$KEY" \
        -p "$port" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        vagrant@127.0.0.1 \
        "sudo ctr -n k8s.io images pull '$img' >/dev/null 2>&1"; then
        ok=true; break
      fi
      sleep $((try * 10))
    done
    $ok && echo "    ok  $img" || echo "    FAIL $img"
  done < "$IMGS_FILE"
done

echo "## 프리페치 완료. 다음: test-cluster/snapshot.sh base-no-cni"
