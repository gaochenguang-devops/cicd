#!/usr/bin/env bash
set -u
export KUBECONFIG=/root/.kube/config
TS=$(date +%Y%m%d-%H%M%S)
BAK=/root/jenkins-sso-bak-$TS
mkdir -p $BAK
kubectl -n jenkins get cm jenkins-casc -o yaml > $BAK/jenkins-casc.yaml
echo "backup -> $BAK"
kubectl -n jenkins create configmap jenkins-casc --from-file=jenkins.yaml=/tmp/jenkins-casc-oidc.yaml --dry-run=client -o yaml | kubectl apply -f -
echo "== reload JCasC =="
python3 - <<'PY'
import urllib.request,urllib.parse,base64,re
BASE="http://127.0.0.1:30088"
H={"Authorization":"Basic "+base64.b64encode(b"lead01:__LDAP_USER_INIT_PASS__").decode()}
def get(p):
    r=urllib.request.Request(BASE+p,headers=H)
    with urllib.request.urlopen(r,timeout=60) as x: return x.read().decode()
crumb=re.search(r'name="Jenkins-Crumb"[^>]*value="([^"]+)"',get("/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,%22:%22,//crumb)")).group(1)
print("crumb:",crumb[:40])
d=urllib.parse.urlencode({"_.crumb":crumb.split(":")[1],"json":"{}","Submit":"Yes"}).encode()
req=urllib.request.Request(BASE+"/configuration-as-code/reload",data=d,headers={**H,"Content-Type":"application/x-www-form-urlencoded"})
try:
    with urllib.request.urlopen(req,timeout=120) as x: print("reload:",x.status, x.read().decode()[:200])
except urllib.error.HTTPError as e: print("reload err:",e.code,e.read().decode()[:400])
PY
