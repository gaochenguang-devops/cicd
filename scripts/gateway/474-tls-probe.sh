#!/bin/bash
set -uo pipefail
kubectl run tls-probe --rm -i --restart=Never --image=192.168.200.12:30090/library/python:3.11-alpine --command -- python3 -c "
import ssl, socket, time
for name,ip in [('VIP','192.168.200.210'),('CIP','10.108.229.246')]:
    ctx=ssl._create_unverified_context()
    try:
        raw=socket.create_connection((ip,443),6)
        t=time.time()
        s=ctx.wrap_socket(raw, server_hostname='keycloak.corp.local')
        print('  %s TLS ok %.2fs proto=%s' % (name, time.time()-t, s.version()))
        s.send(b'GET /realms/corp/.well-known/openid-configuration HTTP/1.1\r\nHost: keycloak.corp.local\r\nConnection: close\r\n\r\n')
        data=s.recv(200)
        print('   ', data.split(b'\r\n')[0])
        s.close()
    except Exception as e:
        print('  %s FAIL %r' % (name, e))
" 2>&1 | tail -10
