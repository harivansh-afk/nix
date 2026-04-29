{
  pkgs,
  username,
  loopbackVhost,
  ...
}:
let
  domain = "harivan.sh";
  port = 8880;
  repoDir = "/home/${username}/Documents/GitHub/website";
in
{
  services.caddy.virtualHosts."http://${domain}" = loopbackVhost port;

  systemd.services.website = {
    description = "Personal website";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      User = username;
      Group = "users";
      WorkingDirectory = repoDir;
      ExecStart = "${pkgs.python3}/bin/python -m http.server ${toString port} --bind 127.0.0.1";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
