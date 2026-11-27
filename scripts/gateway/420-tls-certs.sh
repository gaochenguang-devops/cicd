#!/bin/bash
set -uo pipefail
D=/root/gateway-tls
mkdir -p $D && cd $D

cat > san.cnf <<'EOF'
[req]
distinguished_name = dn
prompt = no
x509_extensions = v3_ca
[dn]
CN = CORP Internal CA
O  = CORP Platform
L  = Nanjing
C  = CN
[v3_ca]
basicConstraints = critical,CA:TRUE,pathlen:0
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
EOF

if [ ! -f ca.crt ]; then
  openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout ca.key -out ca.crt -config san.cnf >/dev/null 2>&1
  echo "CA 已生成"
fi

cat > leaf.cnf <<'EOF'
[req]
distinguished_name = dn
prompt = no
req_extensions = v3_req
[dn]
CN = gateway.corp.local
O  = CORP Platform
[v3_req]
basicConstraints = CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt
[alt]
DNS.1  = corp.local
DNS.2  = *.corp.local
DNS.3  = gitlab.corp.local
DNS.4  = jenkins.corp.local
DNS.5  = harbor.corp.local
DNS.6  = sonar.corp.local
DNS.7  = artifactory.corp.local
DNS.8  = argocd.corp.local
DNS.9  = keycloak.corp.local
DNS.10 = ldapadmin.corp.local
DNS.11 = podinfo.corp.local
DNS.12 = webapp.corp.local
IP.1   = 192.168.200.210
IP.2   = 192.168.200.12
EOF

openssl req -newkey rsa:2048 -nodes -keyout gateway.key -out gateway.csr -config leaf.cnf >/dev/null 2>&1
openssl x509 -req -in gateway.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -days 825 -sha256 -extfile leaf.cnf -extensions v3_req -out gateway.crt >/dev/null 2>&1

echo "=== 证书校验 ==="
openssl verify -CAfile ca.crt gateway.crt
openssl x509 -in gateway.crt -noout -subject -dates -ext subjectAltName | head -8
ls -l $D
