#!/bash/bin
set -uo pipefail
echo "=== kubectl 配置 ==="
mkdir -p /root/.kube
cp -f /etc/kubernetes/admin.conf /root/.kube/config
chmod 600 /root/.kube/config
export KUBECONFIG=/root/.kube/config
grep -q 'KUBECONFIG' /root/.bashrc || cat >>/root/.bashrc <<'EOF'
export KUBECONFIG=/root/.kube/config
EOF

echo "=== 下载 Calico 清单 ==="
curl -sSL --retry 3 -m 120 -o /root/calico.yaml https://cdn.jsdelivr.net/gh/projectcalico/calico@v3.32.3/manifests/calico.yaml
wc -l /root/calico.yaml
grep -n "CALICO_IPV4POOL_CIDR" /root/calico.yaml | head -5

echo "=== 调整 Pod CIDR 为 10.244.0.0/16（与 kubeadm --pod-network-cidr 一致）==="
python3 - <<'PY'
p = "/root/calico.yaml"
s = open(p).read()
old = """            # - name: CALICO_IPV4POOL_CIDR
            #   value: "192.168.0.0/16\""""
new = """            - name: CALICO_IPV4POOL_CIDR
              value: "10.244.0.0/16\""""
if old in s:
    s = s.replace(old, new)
    print("patched with exact block")
elif "192.168.0.0/16" in s:
    s = s.replace('"192.168.0.0/16"', '"10.244.0.0/16"')
    s = s.replace("# - name: CALICO_IPV4POOL_CIDR", "- name: CALICO_IPV4POOL_CIDR")
    s = s.replace("#   value: \"10.244.0.0/16\"", "  value: \"10.244.0.0/16\"")
    print("patched by replace")
open(p, "w").write(s)
PY
grep -n -A1 "CALICO_IPV4POOL_CIDR" /root/calico.yaml | head -6

echo "=== 部署 Calico ==="
kubectl apply -f /root/calico.yaml 2>&1 | tail -10

echo "=== 等待 CNI 就绪 ==="
for i in $(seq 1 40); do
  ready=$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}')
  [ "$ready" = "Ready" ] && break
  sleep 10
done
kubectl get nodes -o wide
kubectl get pods -n kube-system

echo "=== 解除 control-plane 污点（单节点需要运行工作负载）==="
kubectl taint nodes pxe-boot-test-1 node-role.kubernetes.io/control-plane:NoSchedule- 2>&1 || true
kubectl get nodes -o jsonpath='{.items[*].spec.taints}' ; echo
echo "=== CNI DONE ==="
