#!/usr/bin/env bash
set -uo pipefail
REPO_URL="http://root:__GITLAB_PAT__@192.168.200.12/root/cicd-demo.git"
WORK=/root/work/cicd-demo

echo "=== 克隆仓库 ==="
rm -rf $WORK && mkdir -p /root/work
cd /root/work
git clone "$REPO_URL" cicd-demo 2>&1 | tail -3
cd $WORK
git config user.email "root@pxe-boot-test-1"
git config user.name "GitLab Admin"

echo "=== 写入 demo 应用清单 ==="
mkdir -p deploy

cat > deploy/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
EOF

cat > deploy/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-nginx
  labels:
    app: demo-nginx
    managed-by: argocd
spec:
  replicas: 2
  selector:
    matchLabels:
      app: demo-nginx
  template:
    metadata:
      labels:
        app: demo-nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.27-alpine
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi
          readinessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 5
            periodSeconds: 10
EOF

cat > deploy/service.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: demo-nginx
  labels:
    app: demo-nginx
    managed-by: argocd
spec:
  type: NodePort
  selector:
    app: demo-nginx
  ports:
    - name: http
      port: 80
      targetPort: 80
      nodePort: 30081
EOF

cat > deploy/README.md <<'EOF'
# cicd-demo

GitLab 仓库 -> ArgoCD 自动同步示例。

- `deploy/` 目录由 ArgoCD Application `demo-app` 监控
- 修改 replicas / image 并 push，ArgoCD 会自动同步到集群
- 服务访问: http://192.168.200.12:30081
EOF

git add -A
git commit -m "add demo app manifests for argocd" 2>&1 | tail -2
git push origin main 2>&1 | tail -5 || git push origin master 2>&1 | tail -5
git log --oneline -3
echo "=== DEMO REPO DONE ==="
