#!/bin/bash
set -uo pipefail
P=$(kubectl -n jenkins get pod -o name | head -1)
kubectl -n jenkins exec $P -c jenkins -- sh -c 'echo JAVA_HOME=$JAVA_HOME; ls -l $JAVA_HOME/lib/security/cacerts; keytool -list -keystore $JAVA_HOME/lib/security/cacerts -storepass changeit 2>&1 | grep -ci corp; keytool -list -keystore $JAVA_HOME/lib/security/cacerts -storepass changeit 2>&1 | grep -i corp | head -3'
