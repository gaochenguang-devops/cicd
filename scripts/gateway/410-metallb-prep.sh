#!/bin/bash
set -uo pipefail
cd /root
echo "=== 取 MetalLB 0.14.9 原生清单 ==="
if curl -fsSL -o metallb-native.yaml https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml; then
  echo "  raw.githubusercontent OK $(wc -l < metallb-native.yaml) 行"
else
  echo "  raw 失败，走 GitHub API"
  curl -fsSL -H 'Accept: application/vnd.github.raw' \
    -o metallb-native.yaml 'https://api.github.com/repos/metallb/metallb/contents/config/manifests/metallb-native.yaml?ref=v0.14.9'
  echo "  API OK $(wc -l < metallb-native.yaml) 行"
fi
grep -E 'image:' metallb-native.yaml

echo "=== 拉镜像并推到 Harbor library ==="
for img in controller:v0.14.9 speaker:v0.14.9; do
  n=${img%%:*}; t=${img##*:}
  podman pull -q quay.io/metallb/$img >/dev/null 2>&1 || { echo "  pull 失败 $img"; continue; }
  podman tag quay.io/metallb/$img 192.168.200.12:30090/library/metallb-$n:$t
  podman push -q --creds admin:__HARBOR_ADMIN_PASS__ --tls-verify=false 192.168.200.12:30090/library/metallb-$n:$t >/dev/null 2>&1 \
    && echo "  pushed library/metallb-$n:$t" || echo "  push 失败 $img"
done
