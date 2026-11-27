podman push --creds "admin:__HARBOR_ADMIN_PASS__" --tls-verify=false 192.168.200.12:30090/library/eclipse-temurin:21-jre 2>&1 | tail -4
curl -s -u 'admin:__HARBOR_ADMIN_PASS__' 'http://192.168.200.12:30090/api/v2.0/projects/library/repositories?page_size=100' | python3 -c 'import sys,json;[print(" repo:",r["name"]) for r in json.load(sys.stdin)]'
