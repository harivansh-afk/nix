{
  config,
  lib,
  pkgs,
  ...
}:
let
  owner = "harivansh-afk";

  manifest = pkgs.writeText "forgejo-mirror-manifest.json" (
    builtins.toJSON {
      owned_owner = owner;
      push_mirror_interval = "15m0s";
      ignored_orgs = [ ];
      actions_enabled_repos = map (name: "${owner}/${name}") [
        "agentikube"
        "airplay-at-the-crib"
        "betternas"
        "cc-proxy"
        "deskctl"
        "draw"
        "nix"
        "pierrejo"
        "pr.nvim"
        "roomcast"
        "sharefs"
      ];
    }
  );
in
{
  systemd.services.forgejo-mirror-sync = {
    description = "Mirror every GitHub org repo into Forgejo";
    after = [ "forgejo.service" ];
    requires = [ "forgejo.service" ];
    environment = {
      MIRROR_MANIFEST = manifest;
      FORGEJO_API = "http://127.0.0.1:${toString config.services.forgejo.settings.server.HTTP_PORT}/api/v1";
    };
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "6h";
      User = config.services.forgejo.user;
      Group = config.services.forgejo.group;
      EnvironmentFile = [
        config.sops.secrets."forgejo-mirror.env".path
        config.sops.secrets."forgejo-mirror-github-token.env".path
        config.sops.secrets."forgejo-mirror-github-accounts.env".path
      ];
      ExecStart = "${lib.getExe pkgs.python3} ${./mirror-sync.py}";
    };
  };

  systemd.timers.forgejo-mirror-sync = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitInactiveSec = "30min";
    };
  };
}
