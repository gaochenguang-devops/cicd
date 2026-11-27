#!/bin/bash
set -uo pipefail
kubectl get svc -A | grep -vE 'kube-system' | awk '{printf "%-12s %-28s %-10s %s\n", $1,$2,$3,$5}'
