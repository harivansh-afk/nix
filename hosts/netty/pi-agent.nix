{
  pkgs,
  username,
  ...
}:
let
  piAgentEnvFile = "/var/lib/pi-agent/pi-agent.env";
  npmBin = "/home/${username}/.local/share/npm/bin";
  piBin = "${npmBin}/pi";

  piAgentStart = pkgs.writeShellScript "start-pi-agent" ''
    [ -x "${piBin}" ] || { echo "pi not found at ${piBin}" >&2; exit 1; }
    export PATH="${npmBin}:$PATH"
    exec ${pkgs.dtach}/bin/dtach -N /run/pi-agent/pi-agent.sock \
      ${piBin} --chat-bridge
  '';
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/pi-agent 0750 ${username} users -"
    "z ${piAgentEnvFile} 0600 ${username} users -"
    "d /run/pi-agent 0750 ${username} users -"
  ];

  # Pi coding agent running as a Telegram bridge gateway.
  # The main process hosts extensions (pi-channels, pi-schedule-prompt,
  # pi-subagents) and polls Telegram. Actual prompts run in separate
  # pi --mode rpc subprocesses spawned on demand.
  #
  # Config: ~/.pi/agent/settings.json (bot token, bridge settings)
  # API key: /var/lib/pi-agent/pi-agent.env
  systemd.services.pi-agent = {
    description = "Pi Telegram Bridge";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [
      nodejs_22
      git
      dtach
      coreutils
      gnutar
      gzip
    ];
    environment = {
      HOME = "/home/${username}";
      NODE_NO_WARNINGS = "1";
      XDG_DATA_HOME = "/home/${username}/.local/share";
      XDG_CACHE_HOME = "/home/${username}/.cache";
      XDG_CONFIG_HOME = "/home/${username}/.config";
      NPM_CONFIG_USERCONFIG = "/home/${username}/.config/npm/npmrc";
    };
    serviceConfig = {
      Type = "simple";
      User = username;
      Group = "users";
      WorkingDirectory = "/home/${username}";
      ExecCondition = "${pkgs.writeShellScript "pi-env-check" ''
        [ -f "${piAgentEnvFile}" ]
      ''}";
      EnvironmentFile = piAgentEnvFile;
      ExecStart = piAgentStart;
      Restart = "on-failure";
      RestartSec = 10;
    };
  };
}
