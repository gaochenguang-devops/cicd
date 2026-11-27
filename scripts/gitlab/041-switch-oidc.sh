#!/usr/bin/env bash
set -eu
cat >> /etc/gitlab/gitlab.rb <<'EOF'

# ===== Keycloak OIDC SSO（统一账号：OpenLDAP -> Keycloak -> GitLab）=====
gitlab_rails['ldap_enabled'] = false
gitlab_rails['omniauth_enabled'] = true
gitlab_rails['omniauth_allow_single_sign_on'] = ['openid_connect']
gitlab_rails['omniauth_block_auto_created_users'] = false
gitlab_rails['omniauth_auto_link_user'] = ['email']
gitlab_rails['omniauth_providers'] = [
  {
    name: "openid_connect",
    label: "Keycloak 统一登录",
    args: {
      name: "openid_connect",
      scope: ["openid", "profile", "email", "groups"],
      response_type: "code",
      issuer: "http://192.168.200.12:30087/realms/corp",
      discovery: true,
      client_auth_method: "query",
      uid_field: "preferred_username",
      client_options: {
        identifier: "gitlab",
        secret: "__GITLAB_OIDC_SECRET__",
        redirect_uri: "http://192.168.200.12/users/auth/openid_connect/callback"
      }
    }
  }
]
EOF
echo "== reconfigure =="
gitlab-ctl reconfigure 2>&1 | tail -20
