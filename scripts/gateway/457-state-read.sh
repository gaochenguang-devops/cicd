#!/bin/bash
set -uo pipefail
echo "########## gitlab.rb 第 1-90 行 ##########"
sed -n '1,90p' /etc/gitlab/gitlab.rb | grep -vnE '^\s*$' | head -70

echo "########## GitLab Runner 位置 ##########"
kubectl get pods -A 2>/dev/null | grep -i runner
systemctl is-active gitlab-runner 2>/dev/null || true
podman ps 2>/dev/null | grep -i runner || true
ls /etc/gitlab-runner/ 2>/dev/null || true
echo "########## runner config 关键项 ##########"
[ -f /etc/gitlab-runner/config.toml ] && grep -nE "url|tls|cert|clone_url|environment" /etc/gitlab-runner/config.toml | head -20

echo "########## GitLab 当前 trusted-certs ##########"
ls -l /etc/gitlab/trusted-certs/ 2>/dev/null || echo "  (目录不存在)"

echo "########## CA 文件确认 ##########"
ls -l /root/gateway-tls/ca.crt && openssl x509 -in /root/gateway-tls/ca.crt -noout -subject

echo "########## coredns 部署的 容器/挂载 ##########"
kubectl -n kube-system get deploy coredns -o jsonpath='{.spec.template.spec.containers[0].volumeMounts}'; echo
