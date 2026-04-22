{
  inputs,
  pkgs,
  username,
  ...
}:
let
  homeDir = "/home/${username}";
  stateDir = "${homeDir}/.hermes";
in
{
  # The hermes-agent NixOS module orders its activation script after
  # "setupSecrets" (sops-nix / agenix). We don't use either, so
  # provide a no-op to satisfy the dependency.
  system.activationScripts.setupSecrets = "";

  services.hermes-agent = {
    enable = true;
    package = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default;
    user = username;
    group = "users";
    createUser = false;
    stateDir = stateDir;
    workingDirectory = "${stateDir}/workspace";
    addToSystemPackages = false;

    environmentFiles = [ "${stateDir}/.env" ];
    environment = {
      HERMES_MANAGED = "true";
    };

    documents = {
      "SOUL.md" = ../../../dots/hermes/SOUL.md;
      "TOOLS.md" = ../../../dots/hermes/TOOLS.md;
      "HEARTBEAT.md" = ../../../dots/hermes/HEARTBEAT.md;
    };

    settings = {
      model = {
        provider = "openai-codex";
        model = "gpt-5.4";
      };
      agent = {
        max_turns = 100;
        verbose = false;
      };
      terminal = {
        backend = "local";
      };
      compression = {
        enabled = true;
      };
      memory = {
        memory_enabled = true;
        user_profile_enabled = true;
      };
      toolsets = [ "coding" ];
      channels = {
        telegram = {
          bot_token = "\${TELEGRAM_BOT_TOKEN}";
          dm_policy = "pairing";
        };
      };
    };

    mcpServers = { };

    extraPackages = with pkgs; [
      nodejs_22
      git
      docker
    ];

    restart = "always";
    restartSec = 5;
  };
}
