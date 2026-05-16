{
  config,
  pkgs,
  lib,
  ...
}:
let
  ownedOwner = "harivansh-afk";

  noMirror = [
    "${ownedOwner}/cp.nvim"
    "${ownedOwner}/oil.nvim"
    "${ownedOwner}/sandbox-agent"
  ];

  actionsEnabledRepos = [
    "${ownedOwner}/nix"
    "${ownedOwner}/deskctl"
    "${ownedOwner}/betternas"
    "${ownedOwner}/agentikube"
  ];

  manifest = {
    schema = "forgejo-mirror-manifest/v2";
    forgejo_host = "git.harivan.sh";
    owned_owner = ownedOwner;
    push_mirror_interval = "15m0s";
    push_mirror_sync_on_commit = true;
    pull_mirror_interval = "15m";
    no_mirror = noMirror;
    actions_enabled_repos = actionsEnabledRepos;
  };

  manifestJson = pkgs.writeText "forgejo-mirror-manifest.json" (builtins.toJSON manifest);
in
{
  environment.etc."forgejo-mirror/manifest.json".source = manifestJson;
  environment.variables.FORGEJO_MIRROR_MANIFEST = "/etc/forgejo-mirror/manifest.json";
}
