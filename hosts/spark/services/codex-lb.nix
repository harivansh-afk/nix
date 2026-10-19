{
  config,
  inputs,
  pkgs,
  username,
  ...
}:
let
  package = inputs.codex-lb.packages.${pkgs.stdenv.hostPlatform.system}.default;
  state = "${config.users.users.${username}.home}/.local/state/codex-lb";
in
{
  systemd.user.services.codex-lb = {
    description = "Private Codex account gateway";
    wantedBy = [ "default.target" ];
    unitConfig.ConditionUser = username;
    environment = {
      PORT = "18475";
      CODEX_LB_DATA_DIR = state;
      CODEX_LB_TELEMETRY_ENABLED = "false";
      CODEX_LB_OAUTH_CALLBACK_HOST = "127.0.0.1";
    };
    serviceConfig = {
      ExecStartPre = "${pkgs.coreutils}/bin/install -d -m 0700 ${state}";
      ExecStart = "${package}/bin/codex-lb --host 127.0.0.1 --port 18475";
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStopSec = 30;
      NoNewPrivileges = true;
      UMask = "0077";
    };
  };
}
