{
  pkgs,
  username,
  ...
}:
let
  piAgentEnvFile = "/var/lib/pi-agent/pi-agent.env";
  piBin = "/home/${username}/.local/share/npm/bin/pi";

  # Start pi inside an interactive login shell so it inherits the full user
  # environment (PATH, XDG dirs, etc). dtach provides the PTY that pi needs.
  piAgentStart = pkgs.writeShellScript "start-pi-agent" ''
    exec ${pkgs.dtach}/bin/dtach -N /run/pi-agent/pi-agent.sock \
      /run/current-system/sw/bin/zsh -lic 'exec ${piBin} --chat-bridge'
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
  # Runs as a login shell so the agent has the full user environment
  #
  # Config: ~/.pi/agent/settings.json (bot token, bridge settings)
  # API key: /var/lib/pi-agent/pi-agent.env
  systemd.services.pi-agent = {
    description = "Pi Telegram Bridge";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.dtach ];
    serviceConfig = {
      Type = "simple";
      User = username;
      Group = "users";
      WorkingDirectory = "/home/${username}";
      EnvironmentFile = piAgentEnvFile;
      ExecStart = piAgentStart;
      Restart = "on-failure";
      RestartSec = 10;
    };
  };
}
