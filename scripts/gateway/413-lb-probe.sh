#!/bin/bash
set -uo pipefail
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: lb-probe
  namespace: jenkins
spec:
  type: LoadBalancer
  selector:
    app: jenkins
  ports:
    - name: http
      port: 80
      targetPort: 8080
EOF
sleep 6
IP=$(kubectl -n jenkins get svc lb-probe -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "VIP=$IP"
curl -s -o /dev/null -m 8 -w 'http_via_vip=%{http_code}\n' "http://$IP/login" || true
echo "=== 从 VIP 取 crumb ==="
curl -s -m 8 "http://$IP/api/json" -o /dev/null -w 'api=%{http_code}\n'
kubectl -n jenkins delete svc lb-probe --ignore-not-found >/dev/null
echo "探测服务已删除"
