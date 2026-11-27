#!/usr/bin/env bash
set -uo pipefail
export KUBECONFIG=/root/.kube/config
echo "== containerd 现有 registry 配置 =="
grep -nE "config_path|mirrors|endpoint|docker.io" /etc/containerd/config.toml | head -12
echo
echo "== 补 daocloud mirror（若无）=="
if ! grep -q 'docker.m.daocloud.io' /etc/containerd/config.toml; then
cat >> /etc/containerd/config.toml <<'EOF'

[plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
  endpoint = ["https://docker.m.daocloud.io"]
EOF
  echo "  已追加 mirror"
else
  echo "  已存在"
fi
if ! grep -q 'config_path' /etc/containerd/config.toml; then
  sed -i 's#\[plugins."io.containerd.grpc.v1.cri".registry\]#[plugins."io.containerd.grpc.v1.cri".registry]\n  config_path = "/etc/containerd/certs.d"#' /etc/containerd/config.toml
  echo "  已设置 config_path"
fi
echo
echo "== Harbor insecure registry（containerd certs.d）=="
mkdir -p "/etc/containerd/certs.d/192.168.200.12:30090"
cat > "/etc/containerd/certs.d/192.168.200.12:30090/hosts.toml" <<'EOF'
server = "http://192.168.200.12:30090"
[host."http://192.168.200.12:30090"]
  capabilities = ["pull", "resolve"]
  skip_verify = true
EOF
cat "/etc/containerd/certs.d/192.168.200.12:30090/hosts.toml"
systemctl restart containerd
sleep 8
systemctl is-active containerd
kubectl get node --no-headers 2>/dev/null | head -1
echo
echo "== podman insecure 配置 =="
cat > /etc/containers/registries.conf.d/002-harbor.conf <<'EOF'
[[registry]]
location = "192.168.200.12:30090"
insecure = true
EOF
cat /etc/containers/registries.conf.d/002-harbor.conf
echo
echo "== 建数据目录 =="
mkdir -p /data/harbor/{registry,database,joblog,valkey}
ls -d /data/harbor/*
echo
echo "== 静态 PV/PVC =="
cat > /root/harbor-storage.yaml <<'YAML'
apiVersion: v1
kind: PersistentVolume
metadata:
  name: harbor-registry-pv
spec:
  capacity: {storage: 30Gi}
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  hostPath: {path: /data/harbor/registry, type: DirectoryOrCreate}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: harbor-registry-pvc
  namespace: harbor
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: ""
  volumeName: harbor-registry-pv
  resources: {requests: {storage: 30Gi}}
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: harbor-database-pv
spec:
  capacity: {storage: 5Gi}
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  hostPath: {path: /data/harbor/database, type: DirectoryOrCreate}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: harbor-database-pvc
  namespace: harbor
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: ""
  volumeName: harbor-database-pv
  resources: {requests: {storage: 5Gi}}
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: harbor-joblog-pv
spec:
  capacity: {storage: 2Gi}
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  hostPath: {path: /data/harbor/joblog, type: DirectoryOrCreate}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: harbor-joblog-pvc
  namespace: harbor
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: ""
  volumeName: harbor-joblog-pv
  resources: {requests: {storage: 2Gi}}
YAML
kubectl create ns harbor --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply -f /root/harbor-storage.yaml
sleep 3
kubectl -n harbor get pvc
echo
echo "== helm values =="
cat > /root/harbor-values.yaml <<'YAML'
expose:
  type: nodePort
  tls:
    enabled: false
  nodePort:
    name: harbor
    ports:
      http:
        port: 80
        nodePort: 30090
externalURL: http://192.168.200.12:30090
harborAdminPassword: "__HARBOR_ADMIN_PASS__"
persistence:
  enabled: true
  resourcePolicy: "keep"
  persistentVolumeClaim:
    registry:
      existingClaim: harbor-registry-pvc
    jobservice:
      jobLog:
        existingClaim: harbor-joblog-pvc
    database:
      existingClaim: harbor-database-pvc
database:
  type: internal
trivy:
  enabled: false
notary:
  enabled: false
core:
  replicas: 1
portal:
  replicas: 1
jobservice:
  replicas: 1
registry:
  replicas: 1
redis:
  type: internal
YAML
echo "== 安装 Harbor（后台，镜像拉取需数分钟）=="
helm install harbor goharbor/harbor -n harbor -f /root/harbor-values.yaml --timeout 15m 2>&1 | tail -25
