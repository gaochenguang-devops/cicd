#!/bash
set -uo pipefail
echo "########## CoreDNS Corefile ##########"
kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}'
echo
echo "########## CoreDNS 部署 volume/configmap 引用 ##########"
kubectl -n kube-system get deploy coredns -o jsonpath='{.spec.template.spec.volumes}'; echo

echo "########## Sonar settings（用 CI token 鉴权） ##########"
kubectl -n sonar exec deploy/sonarqube -c sonarqube -- sh -c '
curl -s -H "Authorization: Bearer __SONAR_CI_TOKEN__" "http://localhost:9000/api/settings/values" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for s in d.get(\"settings\",[]):
    k=s.get(\"key\",\"\")
    if any(x in k for x in (\"oidc\",\"serverBase\",\"sso\",\"auth\")):
        print(\"  \",k,\"=\",str(s.get(\"value\",s.get(\"values\")))[:110])
"' 2>&1 | head -25
echo "########## Sonar deployment env ##########"
kubectl -n sonar get deploy sonarqube -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' | grep -Ei 'JAVA|OPTS'
echo "########## Harbor 全量 configurations 中与 oidc 相关键 ##########"
kubectl -n harbor exec deploy/harbor-core -c core -- sh -c 'curl -s -u admin:__HARBOR_ADMIN_PASS__ http://localhost:8080/api/v2.0/configurations' 2>&1 | python3 -c '
import json,sys
d=json.load(sys.stdin)
for k,v in d.items():
    if "oidc" in k or k in ("external_url","auth_mode"):
        print("  ",k,"=",str(v.get("value") if isinstance(v,dict) else v)[:120])
' 2>&1 | head -25
