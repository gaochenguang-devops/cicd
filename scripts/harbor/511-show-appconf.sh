#!/usr/bin/env bash
export KUBECONFIG=/root/.kube/config
kubectl -n harbor get cm harbor-core -o jsonpath='{.data.app\.conf}'
