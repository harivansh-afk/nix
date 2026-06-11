{
  config,
  hostConfig,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  jsonFormat = pkgs.formats.json { };
  indexPackages = inputs.index.packages.${pkgs.stdenv.hostPlatform.system};
  # Shared hook scripts from the index flake: the single source of truth that
  # replaced the drifting copies this repo carried in dots/claude/hooks.
  claudeHooks = indexPackages.claude-hooks;
  hookCommand = name: "${config.home.homeDirectory}/.claude/hooks/${name}";
  claudeSettings = jsonFormat.generate "claude-settings.json" (
    {
      "$schema" = "https://json.schemastore.org/claude-code-settings.json";
      env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
      model = "claude-fable-5";
      # Stay on the classic renderer; the v2.1.110+ fullscreen TUI breaks
      # native scrollback / Cmd+f / tmux copy-mode. Override with /tui fullscreen
      # if you want to opt in for a session.
      tui = "default";
      permissions.defaultMode = "bypassPermissions";
      includeCoAuthoredBy = false;
      autoCompactEnabled = true;
      showThinkingSummaries = true;
      statusLine = {
        type = "command";
        command = "${config.home.homeDirectory}/.claude/statusline.sh";
      };
      voiceEnabled = true;
    }
    # On linux the index claude-code wrapper bakes the claude-hooks stanza into
    # its read-only --settings layer, so listing the hooks here as well would
    # register every hook twice (settings layers concatenate hook lists). On
    # darwin the native-installer claude has no baked layer, so this stanza is
    # what wires the hooks; drop it once the macbook can consume the custom
    # claude-code too (blocked on the darwin IFD caveat described above
    # home.packages).
    // lib.optionalAttrs hostConfig.isDarwin {
      hooks = {
        SessionStart = [
          {
            hooks = [
              {
                type = "command";
                command = hookCommand "session-start.sh";
              }
            ];
          }
          {
            hooks = [
              {
                type = "command";
                command = hookCommand "session-id.sh";
                timeout = 5;
              }
            ];
          }
        ];
        PreToolUse = [
          {
            matcher = "Bash";
            hooks = [
              {
                type = "command";
                command = hookCommand "enforce-modern-tools.sh";
              }
            ];
          }
          {
            matcher = "Bash";
            hooks = [
              {
                type = "command";
                command = hookCommand "block-test-output-filtering.sh";
              }
            ];
          }
        ];
      };
    }
  );
in
{
  # The custom Claude Code from the index flake: wraps the upstream binary with
  # the baked claude-hooks stanza, --dangerously-skip-permissions, the house
  # system prompt, and env caps. Installed as the daily driver, defaults as-is.
  # Linux only for now: the package wraps minecraft-sound (an ix rust tool)
  # into PATH, and evaluating that for aarch64-darwin needs index's cargo-unit
  # IFD, which the linux CI runner behind the eval-macbook check cannot build.
  home.packages = lib.optionals hostConfig.isLinux [ indexPackages.claude-code ];

  home.file.".claude/CLAUDE.md".source = ../dots/claude/CLAUDE.md;
  home.file.".claude/commands" = {
    source = ../dots/claude/commands;
    recursive = true;
  };
  home.file.".claude/settings.json".source = claudeSettings;
  home.file.".claude/statusline.sh" = {
    source = ../dots/claude/statusline.sh;
    executable = true;
  };
  # On linux Claude Code no longer reads these (the wrapper bakes store paths);
  # they stay materialized because the codex requirements.toml in
  # system/common.nix points at $HOME/.claude/hooks/<name>, and on darwin the
  # settings stanza above does too.
  home.file.".claude/hooks/session-start.sh".source = "${claudeHooks}/session-start.sh";
  home.file.".claude/hooks/session-id.sh".source = "${claudeHooks}/session-id.sh";
  home.file.".claude/hooks/enforce-modern-tools.sh".source = "${claudeHooks}/enforce-modern-tools.sh";
  home.file.".claude/hooks/block-test-output-filtering.sh".source =
    "${claudeHooks}/block-test-output-filtering.sh";
}
