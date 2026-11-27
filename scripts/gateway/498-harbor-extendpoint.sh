#!/bin/bash
set -uo pipefail
echo "===== 1. 先手工复现 podman login 的两种写法 ====="
grep -h "ci-builder" /root/harbor-ci-creds.txt 2>/dev/null | head -2
echo "--- 当前（Harbor EXT_ENDPOINT 已改 https）---"
PODMAN_USER=$(grep -oE 'robot\$apps\+ci-builder' /root/harbor-ci-creds.txt 2>/dev/null | head -1)
PODMAN_PASS=$(awk -F'[:=]' '/secret|pass/ {print $NF}' /root/harbor-ci-creds.txt 2>/dev/null | tail -1 | tr -d ' ')
echo "  user=$PODMAN_USER pass_len=${#PODMAN_PASS}"
[ -n "$PODMAN_USER" ] && echo "$PODMAN_PASS" | podman login --tls-verify=false -u "$PODMAN_USER" --password-stdin 192.168.200.12:30090 2>&1 | tail -3

echo "===== 2. 把 EXT_ENDPOINT 改回内网 plaintext（CI/kubelet 依赖它） ====="
kubectl -n harbor get cm harbor-core -o jsonpath='{.data.EXT_ENDPOINT}'; echo
kubectl -n harbor get cm harbor-core -o yaml > /tmp/harbor-cm2.yaml
sed -i 's#EXT_ENDPOINT: https://harbor.corp.local#EXT_ENDPOINT: http://192.168.200.12:30090#' /tmp/harbor-cm2.yaml
grep -n "EXT_ENDPOINT" /tmp/harbor-cm2.yaml
kubectl apply -f /tmp/harbor-cm2.yaml | tail -1
kubectl -n harbor rollout restart deploy/harbor-core | tail -1
kubectl -n harbor rollout status deploy/harbor-core --timeout=120s | tail -1
sleep 5
echo "===== 3. 再试一次 login（应恢复成功） ====="
[ -n "$PODMAN_USER" ] && echo "$PODMAN_PASS" | podman login --tls-verify=false -u "$PODMAN_USER" --password-stdin 192.168.200.12:30090 2>&1 | tail -3
