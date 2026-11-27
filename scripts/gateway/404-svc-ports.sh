#!/bin/bash
set -uo pipefail
kubectl get svc -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,PORT:.spec.ports[*].port,TP:.spec.ports[*].targetPort,TYPE:.spec.type' | grep -vE 'kube-system|^NS' | sort
echo "=== 重点服务详情 ==="
for s in jenkins/jenkins harbor/harbor harbor/harbor-core sonar/sonarqube artifactory/artifactory-router argocd/argocd-server keycloak/keycloak podinfo/podinfo webapp/frontend; do
  ns=${s%%/*}; n=${s##*/}
  echo "--- $ns/$n"
  kubectl -n "$ns" get svc "$n" -o jsonpath='{.spec.ports}'; echo
done
