{
  pkgs,
  username,
  ...
}:
let
  betternasDomain = "api.betternas.com";
  betternasRepoDir = "/home/${username}/Documents/GitHub/betterNAS/betterNAS";
  betternasNodeEnvFile = "/var/lib/betternas/node-agent/node-agent.env";
  betternasNodeBinary = "${betternasRepoDir}/apps/node-agent/dist/betternas-node";
  betternasNodeExportPath = "/home/${username}/Documents";
  betternasNodeEnvCheck = pkgs.writeShellScript "betternas-node-env-check" ''
    [ -f "${betternasNodeEnvFile}" ] && [ -x "${betternasNodeBinary}" ] && [ -d "${betternasNodeExportPath}" ]
  '';
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/betternas/node-agent 0750 ${username} users -"
    "z ${betternasNodeEnvFile} 0600 ${username} users -"
  ];

  systemd.services.betternas-control-plane = {
    description = "betterNAS Control Plane";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = username;
      Group = "users";
      WorkingDirectory = "/var/lib/betternas/control-plane";
      ExecStart = "${betternasRepoDir}/apps/control-plane/dist/control-plane";
      EnvironmentFile = "/var/lib/betternas/control-plane/control-plane.env";
      Restart = "on-failure";
      RestartSec = 5;
      StateDirectory = "betternas/control-plane";
    };
  };

  systemd.services.betternas-node = {
    description = "betterNAS Node";
    after = [
      "betternas-control-plane.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      PORT = "8090";
      BETTERNAS_CONTROL_PLANE_URL = "http://127.0.0.1:3100";
      BETTERNAS_NODE_DIRECT_ADDRESS = "https://${betternasDomain}";
      BETTERNAS_EXPORT_PATH = betternasNodeExportPath;
      BETTERNAS_NODE_DISPLAY_NAME = "netty";
    };
    serviceConfig = {
      Type = "simple";
      User = username;
      Group = "users";
      WorkingDirectory = "/var/lib/betternas/node-agent";
      ExecCondition = betternasNodeEnvCheck;
      ExecStart = betternasNodeBinary;
      EnvironmentFile = "-${betternasNodeEnvFile}";
      Restart = "on-failure";
      RestartSec = 5;
      StateDirectory = "betternas/node-agent";
    };
  };
}
