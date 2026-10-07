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
  bbctl = pkgs.beeper-bridge-manager.overrideAttrs (
    finalAttrs: _old: {
      version = "0.15.0";
      src = pkgs.fetchFromGitHub {
        owner = "beeper";
        repo = "bridge-manager";
        tag = "v${finalAttrs.version}";
        hash = "sha256-3vfZmnjPAdTNejlNE0m2Kd63ZRCtsZgTpz5YEBVkC3I=";
      };
      vendorHash = "sha256-X4DbDfiu1VAhFAUT+VH5T4GpeofjhLDdoKwyNVBA9A4=";
    }
  );
  bridges = {
    slack = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
      pname = "mautrix-slack";
      version = "0.2609.1";
      src = pkgs.fetchurl {
        url = "https://github.com/mautrix/slack/releases/download/v${finalAttrs.version}/mautrix-slack-arm64";
        hash = "sha256-cA4Aua0acHjufDKTRExXlRUunA8+gX3S9SqCaz08YE8=";
      };
      dontUnpack = true;
      dontStrip = true;
      dontPatchELF = true;
      installPhase = ''
        runHook preInstall
        install -Dm755 "$src" "$out/bin/mautrix-slack"
        runHook postInstall
      '';
      doInstallCheck = true;
      installCheckPhase = ''
        runHook preInstallCheck
        "$out/bin/mautrix-slack" --version
        "$out/bin/mautrix-slack" --help
        runHook postInstallCheck
      '';
      meta = {
        inherit (pkgs.mautrix-slack.meta)
          description
          homepage
          license
          mainProgram
          ;
        platforms = [ "aarch64-linux" ];
      };
    });
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
