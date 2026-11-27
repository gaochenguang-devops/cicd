#!/bin/bash
set -uo pipefail
kubectl run net-probe --rm -i --restart=Never --image=192.168.200.12:30090/library/python:3.11-alpine --command -- python3 -c "
import socket, time
targets=[('VIP 443','192.168.200.210',443),('CIP 443','10.108.229.246',443),('keycloak NodePort','192.168.200.12',30087),('harbor svc','10.107.110.95',80)]
for name,ip,port in targets:
    s=socket.socket(); s.settimeout(5)
    t=time.time()
    try:
        s.connect((ip,port)); print('  %-18s CONNECT ok %.2fs' % (name, time.time()-t))
    except Exception as e:
        print('  %-18s FAIL %s' % (name, e))
    s.close()
" 2>&1 | tail -8
echo "=== keycloak env 复查 ==="
kubectl -n keycloak get deploy keycloak -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' | grep KC_HOSTNAME
