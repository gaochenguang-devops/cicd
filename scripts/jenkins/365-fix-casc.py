#!/usr/bin/env python3
# 修复：credentials 必须是 JCasC 顶层键，不能放在 jenkins: 下面
import subprocess

cur = subprocess.check_output(
    "kubectl -n jenkins get cm jenkins-casc -o jsonpath='{.data.jenkins\\.yaml}'", shell=True).decode()

lines = cur.splitlines()
idx = next(i for i, l in enumerate(lines) if l.startswith('  credentials:'))
end = next(i for i, l in enumerate(lines) if l.startswith('  securityRealm:'))
block = [l[2:] if l.startswith('  ') else l for l in lines[idx:end]]

rest = lines[:idx] + lines[end:]
out = ['credentials:'] + block[1:] + [''] + rest
new = '\n'.join(out).replace('credentials:\n   ', 'credentials:\n  ')

# 顶层顺序：credentials / jenkins / unclassified 均可
open('/tmp/casc-fixed.yaml', 'w').write(new + '\n')
print("---- 前 20 行 ----")
print('\n'.join((new + '\n').splitlines()[:20]))

print(subprocess.check_output(
    "kubectl -n jenkins create configmap jenkins-casc --from-file=jenkins.yaml=/tmp/casc-fixed.yaml --dry-run=client -o yaml | kubectl apply -f -",
    shell=True).decode())
