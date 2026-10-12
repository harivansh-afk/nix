{
  config,
  inputs,
  pkgs,
  username,
  ...
}:
let
  package = inputs.cc-proxy.packages.${pkgs.stdenv.hostPlatform.system}.default;
  state = "${config.users.users.${username}.home}/.local/state/claude-proxy";
  linkApiKeys = pkgs.writeShellScript "claude-proxy-api-keys" ''
    ${pkgs.coreutils}/bin/install -d -m 0700 ${state}
    ${pkgs.coreutils}/bin/ln -sfn ${config.sops.secrets."claude-proxy-api-keys".path} ${state}/api-keys
  '';
in
{
  systemd.user.services.claude-proxy = {
    description = "Private Claude account gateway";
    wantedBy = [ "default.target" ];
    unitConfig.ConditionUser = username;
    serviceConfig = {
      ExecStartPre = linkApiKeys;
      ExecStart = "${package}/bin/cc-proxy serve";
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStopSec = 30;
      NoNewPrivileges = true;
      UMask = "0077";
    };
  };
}
