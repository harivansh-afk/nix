{ pkgs, username, ... }:
let
  package = pkgs.callPackage ../../../pkgs/claude-proxy { };
in
{
  systemd.user.services.claude-proxy = {
    description = "Private Claude account gateway";
    wantedBy = [ "default.target" ];
    unitConfig.ConditionUser = username;
    environment.PYTHONUNBUFFERED = "1";
    serviceConfig = {
      ExecStart = "${package}/bin/claude-proxy serve";
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStopSec = 30;
      NoNewPrivileges = true;
      UMask = "0077";
    };
  };
}
