#!/usr/bin/env bash
echo "== systeminfo auth_mode =="
curl -s http://127.0.0.1:30090/api/v2.0/systeminfo | python3 -c 'import sys,json;d=json.load(sys.stdin);print("auth_mode:",d.get("auth_mode"),"oidc:",d.get("oidc_provider_name"))'
echo "== /c/oidc/login =="
curl -s -o /dev/null -D - "http://127.0.0.1:30090/c/oidc/login" | grep -iE '^(HTTP|location)' | cut -c1-240
