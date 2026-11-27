#!/usr/bin/env bash
echo "== commenceLogin redirect =="
curl -s -o /dev/null -D - "http://127.0.0.1:30088/securityRealm/commenceLogin?from=%2F" | grep -iE '^(HTTP|location)' | cut -c1-260
echo "== login page hint =="
curl -s "http://127.0.0.1:30088/login" | grep -ioE 'Keycloak|OpenID|LDAP|oic' | sort -u | head
