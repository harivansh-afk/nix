{
  pkgs,
  username,
  ...
}:
let
  piAgentEnvFile = "/var/lib/pi-agent/pi-agent.env";
  piAgentEnvCheck = pkgs.writeShellScript "pi-agent-env-check" ''
    [ -f "${piAgentEnvFile}" ]
  '';

  piBin = "/home/${username}/.local/share/npm/bin/pi";

  # Wrapper that runs pi inside dtach so it gets a PTY (systemd services
  # don't have a terminal) and can be attached to later for debugging:
  #   dtach -a /run/pi-agent/pi-agent.sock
  piAgentStart = pkgs.writeShellScript "start-pi-agent" ''
    if [ ! -x "${piBin}" ]; then
      echo "pi binary not found at ${piBin}" >&2
      exit 1
    fi

    exec ${pkgs.dtach}/bin/dtach -N /run/pi-agent/pi-agent.sock \
      ${piBin} --chat-bridge
  '';
in
{
  # Ensure state directory and env file have correct permissions.
  systemd.tmpfiles.rules = [
    "d /var/lib/pi-agent 0750 ${username} users -"
    "z ${piAgentEnvFile} 0600 ${username} users -"
    "d /run/pi-agent 0750 ${username} users -"
  ];

  # Pi agent running 24/7 inside dtach.
  # Extensions (pi-channels, pi-schedule-prompt, pi-subagents) load
  # inside Pi's process and handle Telegram bridging, scheduled tasks,
  # and background subagent delegation.
  #
  # The --chat-bridge flag auto-enables the Telegram bridge on startup.
  # Telegram bot token lives in ~/.pi/agent/settings.json (see pi-channels docs).
  # ANTHROPIC_API_KEY comes from the env file.
  #
  # Attach for debugging: dtach -a /run/pi-agent/pi-agent.sock
  # Detach with: Ctrl+\
  systemd.services.pi-agent = {
    description = "Pi Coding Agent (24/7)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [
      pkgs.nodejs_22
      pkgs.git
      pkgs.dtach
      pkgs.coreutils
    ];
    environment = {
      HOME = "/home/${username}";
      NODE_NO_WARNINGS = "1";
    };
    serviceConfig = {
      Type = "simple";
      User = username;
      Group = "users";
      WorkingDirectory = "/home/${username}";
      ExecCondition = piAgentEnvCheck;
      EnvironmentFile = piAgentEnvFile;
      ExecStart = piAgentStart;
      Restart = "on-failure";
      RestartSec = 10;
    };
  };
}
