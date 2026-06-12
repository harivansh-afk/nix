# Barrett's spark-build resource pool: a systemd user slice plus the cache
# directories his build tooling expects. Formerly a home-manager module; now
# the slice unit is a nix-store file symlinked into his user unit directory
# by an activation script that runs as barrett.
{
  lib,
  pkgs,
  ...
}:
let
  username = "barrett";
  homeDir = "/home/${username}";
  cacheRoot = "${homeDir}/.cache/spark-builds";
  userUnitDir = "${homeDir}/.config/systemd/user";

  sliceUnit = pkgs.writeText "spark-build.slice" ''
    [Unit]
    Description=Barrett Spark build resource pool

    [Slice]
    CPUQuota=400%
    MemoryMax=24G
    TasksMax=4096
  '';

  setupScript = pkgs.writeShellScript "barrett-spark-builds-setup" ''
    set -eu
    PATH=${pkgs.coreutils}/bin:$PATH

    mkdir -p \
      "${userUnitDir}" \
      ${lib.escapeShellArg "${cacheRoot}/worktrees"} \
      ${lib.escapeShellArg "${cacheRoot}/locks"} \
      ${lib.escapeShellArg "${cacheRoot}/meta"}

    ln -sfn "${sliceUnit}" "${userUnitDir}/spark-build.slice"

    runtime_dir="/run/user/$(id -u)"
    if [ -d "$runtime_dir" ]; then
      export XDG_RUNTIME_DIR="$runtime_dir"
      export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus"
      ${pkgs.systemd}/bin/systemctl --user daemon-reload || true
    fi
  '';
in
{
  system.activationScripts.barrettSparkBuilds = {
    deps = [
      "users"
      "groups"
    ];
    text = ''
      ${pkgs.util-linux}/bin/runuser -u ${username} -- ${setupScript} \
        || echo "warning: barrett spark-builds setup failed" >&2
    '';
  };
}
