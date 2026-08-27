{ config, inputs, ... }:
{
  imports = [ inputs.hermes-agent.nixosModules.default ];

  services.hermes-agent = {
    enable = true;
    user = "rathi";
    group = "users";
    createUser = false;
    stateDir = "/home/rathi/.local/state/hermes";
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
        model = "qwen3.8-27b-nvfp4";
      };
    };
  };
}
