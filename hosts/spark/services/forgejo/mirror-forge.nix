# Hourly git snapshot of the jj-native ix forge into forgejo; the script
# header documents the hand-made bootstrap state. jj-ix is the operator's
# ~/.local/bin binary, not a nix package: pkgs/jj-ix predates the forge's
# current wire surface.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:
let
  home = "/home/${username}";
  mirror = pkgs.writeShellScript "forge-snapshot-mirror" ''
    export HOME=${home}
    export PATH=${
      lib.makeBinPath [
        pkgs.git
        pkgs.rsync
        pkgs.coreutils
      ]
    }
    export STATE_DIR=${home}/.local/state/forge-snapshot
    export JJ=${home}/.local/bin/jj-ix
    export TOKEN_FILE=${config.sops.secrets."forgejo-token".path}
    exec ${pkgs.bash}/bin/bash ${./forge-snapshot-mirror.sh}
  '';
in
{
  systemd.services.forge-snapshot-mirror = {
    description = "Snapshot forge.ix.dev main into forgejo indexable-inc/ix";
    after = [
      "forgejo.service"
      "network-online.target"
    ];
    requires = [ "forgejo.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = username;
      Group = "users";
      ExecStart = mirror;
      # A cold materialization of 170k files, or recovery after a killed
      # run, can take well over an hour; the timer coalesces while active.
      TimeoutStartSec = "3h";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };
  systemd.timers.forge-snapshot-mirror = {
    description = "Hourly forge -> forgejo snapshot";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitActiveSec = "1h";
      AccuracySec = "5min";
      Unit = "forge-snapshot-mirror.service";
    };
  };
}
