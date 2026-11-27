#!/bin/bash
set -uo pipefail
kubectl -n default create secret docker-registry harbor-pull-probe \
  --docker-server=192.168.200.12:30090 \
  --docker-username='robot$apps+jenkins-ci' \
  --docker-password='__HARBOR_ROBOT_JENKINS_SECRET__' \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null && echo "secret ok"

kubectl -n default delete pod maven-demo-pullprobe --ignore-not-found >/dev/null 2>&1
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: maven-demo-pullprobe
spec:
  restartPolicy: Never
  imagePullSecrets:
    - name: harbor-pull-probe
  containers:
    - name: app
      image: 192.168.200.12:30090/apps/maven-demo:1.0.6
      command: ["java", "-version"]
EOF
sleep 12
kubectl -n default get pod maven-demo-pullprobe -o wide
kubectl -n default logs maven-demo-pullprobe 2>&1 | head -6
kubectl -n default describe pod maven-demo-pullprobe 2>/dev/null | grep -E 'Image:|Image ID:|State:|Reason:' | head -8
