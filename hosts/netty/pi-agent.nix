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

  # Wrapper that exec's pi inside tmux's foreground process so systemd
  # tracks the actual PID. When pi dies, tmux exits, systemd sees it
  # and triggers Restart=on-failure.
  piAgentStart = pkgs.writeShellScript "start-pi-agent" ''
    export PATH="${pkgs.nodejs_22}/bin:$PATH"
    npm_prefix="$(npm prefix -g 2>/dev/null)"
    pi_bin="$npm_prefix/bin/pi"

    if [ ! -x "$pi_bin" ]; then
      echo "pi binary not found at $pi_bin" >&2
      exit 1
    fi

    # tmux runs in the foreground (-D) so systemd tracks this process.
    # The inner shell exec's pi so the tmux pane PID *is* the pi PID.
    exec ${pkgs.tmux}/bin/tmux new-session -D -s pi-agent \
      "exec $pi_bin --chat-bridge"
  '';
in
{
  # Ensure state directory and env file have correct permissions.
  systemd.tmpfiles.rules = [
    "d /var/lib/pi-agent 0750 ${username} users -"
    "z ${piAgentEnvFile} 0600 ${username} users -"
  ];

  # Pi agent running 24/7 in a foreground tmux session.
  # Extensions (pi-channels, pi-schedule-prompt, pi-subagents) load
  # inside Pi's process and handle Telegram bridging, scheduled tasks,
  # and background subagent delegation.
  #
  # The --chat-bridge flag auto-enables the Telegram bridge on startup.
  # Telegram bot token lives in ~/.pi/agent/settings.json (see pi-channels docs).
  # ANTHROPIC_API_KEY comes from the env file.
  #
  # tmux session name: pi-agent
  # Attach for debugging: tmux attach -t pi-agent
  systemd.services.pi-agent = {
    description = "Pi Coding Agent (24/7)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [
      pkgs.nodejs_22
      pkgs.git
      pkgs.tmux
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
