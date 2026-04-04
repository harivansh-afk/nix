{
  inputs,
  pkgs,
  username,
  ...
}:
let
  homeDir = "/home/${username}";
  stateDir = "${homeDir}/.openclaw";
  runtimeConfig = "${stateDir}/openclaw.json";
in
{
  services.openclaw-gateway = {
    enable = true;
    package = inputs.openClaw.packages.${pkgs.stdenv.hostPlatform.system}.default;
    port = 2470;
    user = username;
    group = "users";
    createUser = false;
    stateDir = stateDir;
    environmentFiles = [ "${stateDir}/.env" ];
    environment = {
      OPENCLAW_NIX_MODE = "1";
      OPENCLAW_CONFIG_PATH = runtimeConfig;
    };
    execStart = "${homeDir}/.local/share/npm/bin/openclaw gateway --port 2470";
    execStartPre = [
      "+${pkgs.coreutils}/bin/install -m 600 -o ${username} -g users /etc/openclaw/openclaw.json ${runtimeConfig}"
    ];
    servicePath = with pkgs; [
      pkgs.nodejs_22
      git
      docker
    ];
    config = {
      gateway = {
        mode = "local";
        bind = "loopback";
        port = 2470;
        trustedProxies = [ "127.0.0.1" "::1" ];
        controlUi.allowedOrigins = [ "https://netty.harivan.sh" ];
        auth = {
          mode = "token";
          token = "\${OPENCLAW_GATEWAY_TOKEN}";
        };
      };
      channels.telegram = {
        botToken = "\${TELEGRAM_BOT_TOKEN}";
        dmPolicy = "pairing";
      };
      agents.defaults = {
        workspace = "~/.openclaw/workspace";
        skipBootstrap = false;
        model = {
          primary = "anthropic/claude-opus-4-6";
          fallbacks = [ "anthropic/claude-sonnet-4-6" ];
        };
        sandbox.mode = "off";
      };
      tools = {
        profile = "coding";
        fs.workspaceOnly = true;
        loopDetection.enabled = true;
        deny = [ "sessions_send" "sessions_spawn" ];
      };
    };
  };
}
