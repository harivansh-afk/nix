{
  config,
  lib,
  pkgs,
  username,
  ...
}:
let
  home = config.users.users.${username}.home;
  configDir = "${home}/.config/bbctl";
  dataDir = "${home}/.local/share/bbctl";
  bbctl = pkgs.beeper-bridge-manager.overrideAttrs (old: rec {
    version = "0.15.0";
    src = pkgs.fetchFromGitHub {
      owner = "beeper";
      repo = "bridge-manager";
      tag = "v${version}";
      hash = "sha256-3vfZmnjPAdTNejlNE0m2Kd63ZRCtsZgTpz5YEBVkC3I=";
    };
    vendorHash = "sha256-X4DbDfiu1VAhFAUT+VH5T4GpeofjhLDdoKwyNVBA9A4=";
  });
  bridges = {
    slack = pkgs.mautrix-slack.override { withGoolm = true; };
  };
  mkBridge = name: bridge: {
    name = "beeper-${name}";
    value = {
      description = "Self-hosted ${name} bridge for Beeper";
      wantedBy = [ "default.target" ];
      unitConfig = {
        ConditionUser = username;
        ConditionPathExists = "${configDir}/config.json";
      };
      path = [ pkgs.ffmpeg ];
      environment = {
        BBCTL_CONFIG = "${configDir}/config.json";
        BBCTL_DATA_HOME = "${home}/.local/share";
        BBCTL_COLOR = "never";
      };
      serviceConfig = {
        ExecStart = "${lib.getExe bbctl} run --no-override-config --custom-startup-command ${lib.getExe bridge} sh-${name}";
        Restart = "always";
        RestartSec = 30;
        TimeoutStopSec = 15;
        NoNewPrivileges = true;
        UMask = "0077";
      };
    };
  };
in
{
  users.users.${username}.packages = [ bbctl ];

  systemd.tmpfiles.rules = [
    "d ${configDir} 0700 ${username} users - -"
    "d ${dataDir} 0700 ${username} users - -"
  ];

  systemd.user.services = lib.mapAttrs' mkBridge bridges;
}
