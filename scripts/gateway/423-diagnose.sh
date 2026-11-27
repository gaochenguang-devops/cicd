#!/bin/bash
set -uo pipefail
VIP=192.168.200.210
echo "=== gitlab 302 指向哪里 ==="
curl -s -k -o /dev/null -D - --resolve gitlab.corp.local:443:$VIP https://gitlab.corp.local/ | grep -iE '^location|^http'
echo "=== keycloak 302 指向 ==="
curl -s -k -o /dev/null -D - --resolve keycloak.corp.local:443:$VIP https://keycloak.corp.local/ | grep -iE '^location|^http'
echo "=== jenkins 403 正文 ==="
curl -s -k --resolve jenkins.corp.local:443:$VIP https://jenkins.corp.local/ | sed 's/<[^>]*>/ /g' | tr -s ' \n' ' \n' | head -8
echo "=== 宿主 8090 是否在监听 ==="
ss -ltnp 2>/dev/null | grep -E ':8090|:80 ' | head -5
podman ps --format '{{.Names}} {{.Status}} {{.Ports}}' | head -6
echo "=== Jenkins 直接访问对比（NodePort） ==="
curl -s -o /dev/null -w '  nodeport=%{http_code}\n' http://192.168.200.12:30088/
