#!/usr/bin/env bash
set -u
echo "== login page has Keycloak button? =="
curl -s http://127.0.0.1:80/users/sign_in | grep -ioE 'Keycloak[^<]*|omniauth|openid_connect' | sort -u | head
echo "== auth redirect =="
curl -s -o /dev/null -D - "http://127.0.0.1:80/users/auth/openid_connect" | grep -iE '^(HTTP|location)' | cut -c1-260
