#!/usr/bin/env bash
echo "=== argocd-server 是否有多语言相关参数 ==="
kubectl -n argocd exec deploy/argocd-server -- argocd-server --help 2>&1 | grep -iE "lang|locale|i18n" || echo "(无相关参数)"

echo "=== UI 静态资源位置与语言文件 ==="
kubectl -n argocd exec deploy/argocd-server -- sh -c 'ls /usr/local/share/ 2>/dev/null; ls /usr/local/share/argocd 2>/dev/null | head; find / -maxdepth 5 -iname "*locale*" -o -maxdepth 5 -iname "*i18n*" 2>/dev/null | head -10'

echo "=== index.html 中引用的 JS ==="
curl -sS -m 10 http://127.0.0.1:30080/ | grep -oE '(src|href)="[^"]+\.(js|css)"' | head -10
