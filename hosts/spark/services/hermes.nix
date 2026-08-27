{ config, inputs, ... }:
let
  stateDir = "/home/rathi/.local/state/hermes";
in
{
  imports = [ inputs.hermes-agent.nixosModules.default ];

  systemd.tmpfiles.rules = [
    "L+ ${stateDir}/.hermes/plugins/knowledge-base - - - - /home/rathi/Documents/Git/nix/dots/hermes/plugins/knowledge-base"
    "L+ ${stateDir}/workspace/kb-staging - - - - /var/lib/kb/staging"
  ];

  services.hermes-agent = {
    enable = true;
    user = "rathi";
    group = "users";
    createUser = false;
    inherit stateDir;
    addToSystemPackages = true;

    environmentFiles = [ config.sops.secrets."anthropic.env".path ];

    backend = {
      mode = "serve";
      host = "spark-ix.tail368802.ts.net";
      waitFor = "hostname";
      sessionTokenFile = config.sops.secrets."hermes-backend-token".path;
    };

    settings = {
      model = {
        provider = "openai-codex";
        default = "gpt-5.6-sol";
        api_mode = "codex_responses";
      };
      providers.spark = {
        base_url = "http://127.0.0.1:18080/v1";
        api_mode = "chat_completions";
        model = "qwen3.8-27b";
      };
    };
  };
}
