#!/usr/bin/env bash
set -u
echo "== sysctl for elasticsearch =="
grep -q 'vm.max_map_count=262144' /etc/sysctl.d/99-elastic.conf 2>/dev/null || echo 'vm.max_map_count=262144' > /etc/sysctl.d/99-elastic.conf
sysctl -w vm.max_map_count=262144
sysctl -w fs.file-max=131072 >/dev/null
echo "== dirs =="
mkdir -p /data/sonarqube/{pg,data,plugins} /data/artifactory/{pg,data}
chown -R 1000:0 /data/sonarqube/data /data/sonarqube/plugins
chown -R 1030:1030 /data/artifactory
cd /root/sonar-jfrog
echo "== apply sonar =="
kubectl apply -f manifests/sonar/00-base.yaml
kubectl apply -f manifests/sonar/10-deployment.yaml
echo "== apply artifactory =="
kubectl apply -f manifests/artifactory/00-base.yaml
kubectl apply -f manifests/artifactory/10-deployment.yaml
sleep 5
kubectl -n sonar get pods -o wide
kubectl -n artifactory get pods -o wide
