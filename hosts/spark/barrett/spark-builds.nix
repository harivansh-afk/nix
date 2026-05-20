{
  config,
  lib,
  ...
}:
let
  cacheRoot = "${config.xdg.cacheHome}/spark-builds";
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
}
