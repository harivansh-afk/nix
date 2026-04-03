{
  pkgs,
  username,
  ...
}:
let
  homeDir = "/home/${username}";
  openClawStateDir = "${homeDir}/.openclaw";
  openClawConfigPath = "${openClawStateDir}/openclaw.json";
  openClawEnvFile = "${openClawStateDir}/.env";
  openClawBin = "${homeDir}/.local/share/npm/bin/openclaw";
  openClawCheck = pkgs.writeShellScript "openclaw-gateway-check" ''
    [ -x "${openClawBin}" ] && [ -f "${openClawConfigPath}" ] && [ -s "${openClawEnvFile}" ]
  '';
in
{
  systemd.tmpfiles.rules = [
    "d ${openClawStateDir} 0700 ${username} users -"
    "d ${openClawStateDir}/workspace 0700 ${username} users -"
    "z ${openClawEnvFile} 0600 ${username} users -"
    "z ${openClawConfigPath} 0600 ${username} users -"
  ];

  systemd.services.openclaw-gateway = {
    description = "OpenClaw Gateway";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [
      nodejs_22
      git
      coreutils
      findutils
      gnugrep
      gawk
      docker
    ];
    environment = {
      HOME = homeDir;
      NODE_NO_WARNINGS = "1";
      OPENCLAW_NIX_MODE = "1";
      OPENCLAW_STATE_DIR = openClawStateDir;
      OPENCLAW_CONFIG_PATH = openClawConfigPath;
      NPM_CONFIG_USERCONFIG = "${homeDir}/.config/npm/npmrc";
      XDG_CACHE_HOME = "${homeDir}/.cache";
      XDG_CONFIG_HOME = "${homeDir}/.config";
      XDG_DATA_HOME = "${homeDir}/.local/share";
    };
    serviceConfig = {
      Type = "simple";
      User = username;
      Group = "users";
      WorkingDirectory = openClawStateDir;
      ExecCondition = openClawCheck;
      EnvironmentFile = "-${openClawEnvFile}";
      ExecStart = "${openClawBin} gateway run";
      Restart = "always";
      RestartSec = 5;
    };
  };
}
