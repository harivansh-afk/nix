{ lib, pkgs, ... }:
let
  teaConfigTemplate = pkgs.writeText "tea-config.yml" ''
    logins:
        - name: harivan
          url: https://git.harivan.sh
          token: __TOKEN__
          default: true
          ssh_host: git.harivan.sh
          ssh_key: ""
          insecure: false
          ssh_certificate_principal: ""
          ssh_agent: false
          ssh_key_agent_pub: ""
          version_check: true
          user: harivansh-afk
    preferences:
        editor: false
        flag_defaults:
            remote: ""
  '';
in
{
  home.packages = [ pkgs.tea ];

  home.activation.teaLogin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    tokenFile=/run/secrets/forgejo-token.env
    if [ -r "$tokenFile" ]; then
      token=$(cat "$tokenFile")
      ${pkgs.coreutils}/bin/install -d -m 0700 "$HOME/.config/tea"
      umask 077
      tmp="$HOME/.config/tea/config.yml.tmp"
      ${pkgs.gnused}/bin/sed "s|__TOKEN__|$token|" ${teaConfigTemplate} > "$tmp"
      mv "$tmp" "$HOME/.config/tea/config.yml"
    fi
  '';
}
