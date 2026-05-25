{ lib, pkgs, ... }:
let
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
in
{
  home.packages = [ pkgs.tea ];

  home.activation.teaLogin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    harivanTokenFile=/run/secrets/forgejo-token.env
    ixTokenEnvFile=/run/secrets/forgejo-ix.env

    harivanToken=
    if [ -r "$harivanTokenFile" ]; then
      harivanToken=$(cat "$harivanTokenFile")
    fi

    ixToken=
    if [ -r "$ixTokenEnvFile" ]; then
      ixToken=$(
        set -a
        . "$ixTokenEnvFile"
        printf '%s' "$FORGEJO_IX_TOKEN"
      )
    fi

    if [ -n "$harivanToken" ] || [ -n "$ixToken" ]; then
      ${pkgs.coreutils}/bin/install -d -m 0700 "$HOME/.config/tea"
      umask 077
      tmp="$HOME/.config/tea/config.yml.tmp"

      {
        printf '%s\n' "logins:"
        if [ -n "$harivanToken" ]; then
          ${teaLoginYaml} harivan https://git.harivan.sh git.harivan.sh "$harivanToken" true
        fi
        if [ -n "$ixToken" ]; then
          if [ -n "$harivanToken" ]; then
            ixDefault=false
          else
            ixDefault=true
          fi
          ${teaLoginYaml} ix-harivansh https://git.ix.dev git.ix.dev "$ixToken" "$ixDefault"
        fi
        cat <<'YAML'
    preferences:
        editor: false
        flag_defaults:
            remote: ""
    YAML
      } > "$tmp"

      mv "$tmp" "$HOME/.config/tea/config.yml"
    fi
  '';
}
