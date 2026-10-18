{
  pkgs,
  ...
}:
let
  ownedOwner = "harivansh-afk";

  actionsEnabledRepos = [
    "${ownedOwner}/nix"
    "${ownedOwner}/cc-proxy"
    "${ownedOwner}/pr.nvim"
    "${ownedOwner}/roomcast"
    "${ownedOwner}/airplay-at-the-crib"
    "${ownedOwner}/pierrejo"
    "${ownedOwner}/deskctl"
    "${ownedOwner}/betternas"
    "${ownedOwner}/agentikube"
    "${ownedOwner}/draw"
    "${ownedOwner}/sharefs"
  ];

  githubCanonicalRepos = [
    "${ownedOwner}/TouchedTips"
  ];

  retiredMirrorOwners = [
    "companion-inc"
    "agentcomputerai"
    "dueflow-co"
  ];

  manifest = {
    schema = "forgejo-mirror-manifest/v1";
    forgejo_host = "git.harivan.sh";
    owned_owner = ownedOwner;
    push_mirror_interval = "15m0s";
    push_mirror_sync_on_commit = true;
    pull_mirror_interval = "15m";
    actions_enabled_repos = actionsEnabledRepos;
    retired_mirror_owners = retiredMirrorOwners;
    github_canonical_repos = githubCanonicalRepos;
  };

  manifestJson = pkgs.writeText "forgejo-mirror-manifest.json" (builtins.toJSON manifest);
in
{
  environment.etc."forgejo-mirror/manifest.json".source = manifestJson;
  environment.variables.FORGEJO_MIRROR_MANIFEST = "/etc/forgejo-mirror/manifest.json";
}
