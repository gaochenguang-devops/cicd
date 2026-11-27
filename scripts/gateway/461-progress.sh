#!/bin/bash
set -uo pipefail
echo "=== 进度快照 $(date +%T) ==="
echo "--- hosts:"; grep -c corp.local /etc/hosts || true
echo "--- 系统 CA:"; ls -l /etc/pki/ca-trust/source/anchors/ 2>/dev/null
echo "--- gitlab trusted-certs:"; ls /etc/gitlab/trusted-certs/ 2>/dev/null
echo "--- coredns cm:"; kubectl -n kube-system get cm coredns-corp-hosts -o name 2>/dev/null; kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' | grep -c 'corp.local'
echo "--- secrets:"; kubectl -n jenkins get secret jenkins-java-cacerts 2>/dev/null; kubectl -n sonar get secret sonar-java-cacerts 2>/dev/null
echo "--- pods:"; kubectl -n jenkins get pods; kubectl -n sonar get pods; kubectl -n kube-system get pods -l k8s-app=kube-dns
echo "--- 有无卡住的进程:"; ps -eo pid,etimes,cmd | grep -E 'update-ca-trust|kubectl cp|keytool' | grep -v grep | head -5
