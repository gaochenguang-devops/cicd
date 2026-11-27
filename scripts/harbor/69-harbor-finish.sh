#!/usr/bin/env bash
set -uo pipefail
export KUBECONFIG=/root/.kube/config
echo "== 为 valkey 的 StatefulSet 预置存储 =="
cat > /root/harbor-valkey.yaml <<'YAML'
apiVersion: v1
kind: PersistentVolume
metadata:
  name: harbor-valkey-pv
spec:
  capacity: {storage: 2Gi}
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  hostPath: {path: /data/harbor/valkey, type: DirectoryOrCreate}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-harbor-redis-0
  namespace: harbor
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: ""
  volumeName: harbor-valkey-pv
  resources: {requests: {storage: 1Gi}}
YAML
kubectl apply -f /root/harbor-valkey.yaml
sleep 5
kubectl -n harbor get pvc | head -5
echo
echo "== 等待 Harbor 就绪（最多 4 分钟）=="
for i in $(seq 1 48); do
  R=$(kubectl -n harbor get pods --no-headers 2>/dev/null | awk '{print $2}' | grep -c "1/1\|2/2")
  T=$(kubectl -n harbor get pods --no-headers 2>/dev/null | wc -l)
  echo "  +$(( i*5 ))s ready=$R/$T"
  [ "$R" = "$T" ] && [ "$T" -ge 6 ] && break
  sleep 5
done
kubectl -n harbor get pods
echo
echo "== UI / API =="
curl -s -o /dev/null -w "  UI http=%{http_code}\n" http://192.168.200.12:30090/
curl -s -u "admin:__HARBOR_ADMIN_PASS__" -o /tmp/sys.json -w "  systeminfo http=%{http_code}\n" http://192.168.200.12:30090/api/v2.0/systeminfo
head -c 300 /tmp/sys.json; echo
