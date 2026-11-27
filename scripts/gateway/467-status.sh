#!/bin/bash
set -uo pipefail
echo "=== sonar 镜像 ==="
kubectl -n sonar get deploy sonarqube -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
echo "=== secrets ==="
kubectl -n jenkins get secret jenkins-java-cacerts 2>&1 | tail -1
kubectl -n sonar get secret sonar-java-cacerts 2>&1 | tail -1
echo "=== 临时 pod ==="
kubectl -n jenkins get pods 2>&1 | head -5
kubectl -n sonar get pods 2>&1 | head -5
echo "=== 当前挂载 ==="
kubectl -n jenkins get deploy jenkins -o jsonpath='{.spec.template.spec.containers[0].volumeMounts}'; echo
kubectl -n sonar get deploy sonarqube -o jsonpath='{.spec.template.spec.containers[0].volumeMounts}'; echo
