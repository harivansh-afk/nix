{
  config,
  inputs,
  pkgs,
  username,
  ...
}:
let
  port = 39473;
in
{
  imports = [ "${inputs.copyparty-src}/contrib/nixos/modules/copyparty.nix" ];

  services.copyparty = {
    enable = true;
    package = import ../../../pkgs/copyparty { inherit pkgs; };
    mkHashWrapper = false;
    settings = {
      i = "127.0.0.1";
      p = port;
      no-reload = true;
      hist = "/var/cache/copyparty";
      e2d = true;
      shr = "/s";
      shr-db = "/var/lib/copyparty/shares.db";
      shr-site = "https://files.harivan.sh/";
      shr-adm = username;
      no-html = true;
      no-logues = true;
      no-readme = true;
      no-robots = true;
      unpost = 0;
      pw-urlp = "A";
      rproxy = -1;
      xff-hdr = "cf-connecting-ip";
      xff-src = "127.0.0.1";
    };
    accounts.${username}.passwordFile = config.sops.secrets."copyparty-password".path;
    volumes."/" = {
      path = "/var/lib/copyparty/files";
      access.A = username;
      flags.rw_edit = "md,markdown,txt";
    };
  };

  services.caddy.virtualHosts."http://files.harivan.sh" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      header Cache-Control "private, no-store"
      header X-Robots-Tag "noindex, nofollow"
      reverse_proxy 127.0.0.1:${toString port} {
        header_up X-Forwarded-Proto https
      }
    '';
  };

  systemd.services.copyparty.serviceConfig.Restart = "on-failure";
}
