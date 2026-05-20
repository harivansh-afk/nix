{
  config,
  lib,
  pkgs,
  ...
}:
let
  cacheRoot = "${config.xdg.cacheHome}/spark-builds";
  pruneScript = pkgs.writeShellScript "spark-build-prune" ''
    set -eu
    root=${lib.escapeShellArg cacheRoot}
    worktrees="$root/worktrees"
    mkdir -p "$worktrees" "$root/locks" "$root/meta"
    ${pkgs.findutils}/bin/find "$worktrees" -mindepth 2 -maxdepth 2 -type d -mtime +7 \
      -exec ${pkgs.coreutils}/bin/rm -rf {} +
    ${pkgs.findutils}/bin/find "$worktrees" -mindepth 1 -maxdepth 1 -type d -empty -delete
    ${pkgs.findutils}/bin/find "$root/locks" "$root/meta" -type f -mtime +7 -delete 2>/dev/null || true
  '';
in
{
  xdg.configFile."systemd/user/spark-build.slice".text = ''
    [Unit]
    Description=Barrett Spark build resource pool

    [Slice]
    CPUQuota=400%
    MemoryMax=24G
    TasksMax=4096
  '';

  home.activation.ensureSparkBuildDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p ${lib.escapeShellArg cacheRoot}/worktrees
    mkdir -p ${lib.escapeShellArg cacheRoot}/locks
    mkdir -p ${lib.escapeShellArg cacheRoot}/meta
  '';

  systemd.user.services.spark-build-prune = {
    Unit.Description = "Prune Barrett Spark build cache";
    Service = {
      Type = "oneshot";
      ExecStart = "${pruneScript}";
    };
  };

  systemd.user.timers.spark-build-prune = {
    Unit.Description = "Daily prune of Barrett Spark build cache";
    Timer = {
      OnCalendar = "daily";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
