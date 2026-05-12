{
  lib,
  pkgs,
  username,
  ...
}:
let
  repoDir = "/home/${username}/Documents/Git/indexable/claude-demo";
  port = 4050;
  path = lib.makeBinPath [
    pkgs.bun
    pkgs.coreutils
    pkgs.git
    pkgs.nodejs_24
    pkgs.python3
  ];
in
{
  services.tailscale.serve = {
    enable = true;
    services.claude-demo.endpoints."tcp:443" = "http://127.0.0.1:${toString port}";
  };

  systemd.services.claude-demo = {
    description = "Indexable Claude demo";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      HOME = "/home/${username}";
    };

    serviceConfig = {
      Type = "simple";
      User = username;
      Group = "users";
      WorkingDirectory = repoDir;
      Environment = "PATH=${path}";
      ExecStartPre = [
        "${pkgs.bun}/bin/bun install --frozen-lockfile"
        "${pkgs.bun}/bin/bun run build"
      ];
      ExecStart = "${pkgs.python3}/bin/python -m http.server ${toString port} --bind 127.0.0.1 --directory ${repoDir}/build";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };
}
