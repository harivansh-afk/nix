{
  inputs,
  pkgs,
  username,
  ...
}:
let
  package = inputs.cc-proxy.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  systemd.user.services.claude-proxy = {
    description = "Private Claude account gateway";
    wantedBy = [ "default.target" ];
    unitConfig.ConditionUser = username;
    serviceConfig = {
      ExecStart = "${package}/bin/cc-proxy serve";
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStopSec = 30;
      NoNewPrivileges = true;
      UMask = "0077";
    };
  };
}
