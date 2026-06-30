# tea login fragment: emits one `logins:` entry, called once per forgejo
# instance by the activation script with tokens read from sops secrets.
{ pkgs, ... }:
{
  teaLoginYaml = pkgs.writeShellScript "tea-login-yaml" ''
    set -eu

    name="$1"
    url="$2"
    sshHost="$3"
    token="$4"
    default="$5"

    cat <<YAML
        - name: $name
          url: $url
          token: $token
          default: $default
          ssh_host: $sshHost
          ssh_key: ""
          insecure: false
          ssh_certificate_principal: ""
          ssh_agent: false
          ssh_key_agent_pub: ""
          version_check: false
          user: harivansh-afk
    YAML
  '';
}
