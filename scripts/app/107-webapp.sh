#!/usr/bin/env bash
set -uo pipefail
cd /tmp/podinfo-src
for f in $(find deploy/webapp -type f | sort); do
  echo "---- $f ----"; cat "$f"; echo
done
