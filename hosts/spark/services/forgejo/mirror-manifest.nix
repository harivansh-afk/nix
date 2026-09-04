{
  pkgs,
  ...
}:
let
  ownedOwner = "harivansh-afk";

  actionsEnabledRepos = [
    "${ownedOwner}/nix"
    "${ownedOwner}/pierrejo"
    "${ownedOwner}/deskctl"
    "${ownedOwner}/betternas"
    "${ownedOwner}/agentikube"
  ];

  # Owned repos whose source of truth is GitHub: they live on the forge as
  # inbound pull mirrors and reconcile.sh never gives them a push-mirror.
  # TouchedTips builds on Xcode Cloud from GitHub and merges there.
  githubCanonicalRepos = [
    "${ownedOwner}/TouchedTips"
  ];

  # Owners (lower_name) whose pull mirrors are retired: reconcile.sh converts
  # their mirrors to regular repos (data kept) even if the upstream is still
  # reachable. One-way per repo: re-enabling means re-migrating as a mirror.
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
