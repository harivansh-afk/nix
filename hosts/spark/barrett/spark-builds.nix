{
  config,
  lib,
  ...
}:
let
  cacheRoot = "${config.xdg.cacheHome}/spark-builds";
in
{
  files.".config/systemd/user/spark-build.slice".text = ''
    [Unit]
    Description=Barrett Spark build resource pool

    [Slice]
    CPUQuota=400%
    MemoryMax=24G
    TasksMax=4096
  '';

  dirs = [
    "${cacheRoot}/worktrees"
    "${cacheRoot}/locks"
    "${cacheRoot}/meta"
  ];
}
