#!/usr/bin/env bash
set -u
for t in 16 16-alpine 17 15; do
  echo -n "postgres:$t -> "
  timeout 30 podman pull -q "docker.io/library/postgres:$t" >/dev/null 2>&1 && echo OK || echo FAIL
done
podman images | grep -E 'postgres|keycloak'
