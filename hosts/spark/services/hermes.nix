{ config, inputs, ... }:
let
  stateDir = "/home/rathi/.local/state/hermes";
in
{
  imports = [ inputs.hermes-agent.nixosModules.default ];

  networking.hosts."100.114.116.11" = [ "spark-ix.tail368802.ts.net" ];

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

    # anthropic.env: ANTHROPIC_API_KEY for the anthropic lane.
    # hermes-dashboard.env: the basic-auth provider. A non-loopback bind
    # refuses to start without an auth provider, and the desktop signs in
    # against it once (the session survives restarts via the signing secret).
    environmentFiles = [
      config.sops.secrets."anthropic.env".path
      config.sops.secrets."hermes-dashboard.env".path
    ];

    backend = {
      mode = "serve";
      host = "spark-ix.tail368802.ts.net";
      waitFor = "hostname";
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
