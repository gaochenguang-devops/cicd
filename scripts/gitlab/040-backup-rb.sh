#!/usr/bin/env bash
set -u
TS=$(date +%Y%m%d-%H%M%S)
cp -a /etc/gitlab/gitlab.rb /root/gitlab.rb.bak-$TS
echo "backup: /root/gitlab.rb.bak-$TS"
grep -n "ldapmain\|ldap_enabled\|omniauth" /etc/gitlab/gitlab.rb | head -20
