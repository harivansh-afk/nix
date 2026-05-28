{
  pkgs,
  username,
  ...
}:
let
  ixRepoDir = "/home/${username}/Documents/Git/indexable/ix";
  playbookSubdir = "${ixRepoDir}/playbook";
  port = 4060;

  path = pkgs.lib.makeBinPath [
    pkgs.bash
    pkgs.bun
    pkgs.coreutils
    pkgs.nodejs_24
  ];
in
{
  systemd.services.playbook = {
    description = "Indexable Playbook UI (SvelteKit adapter-node), served from indexable-inc/ix/playbook/";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      HOME = "/home/${username}";
      NODE_ENV = "production";
      PORT = toString port;
      HOST = "127.0.0.1";
      ORIGIN = "http://127.0.0.1:${toString port}";
      PROTOCOL_HEADER = "x-forwarded-proto";
      HOST_HEADER = "x-forwarded-host";
      CODEX_VIEWER_ENABLED = "1";
    };

    serviceConfig = {
      Type = "simple";
      User = username;
      Group = "users";
      WorkingDirectory = playbookSubdir;
      Environment = "PATH=${path}";
      ExecStartPre = [
        "${pkgs.bun}/bin/bun install --frozen-lockfile"
        "${pkgs.bun}/bin/bun run build"
      ];
      ExecStart = "${pkgs.nodejs_24}/bin/node build/index.js";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };
}
