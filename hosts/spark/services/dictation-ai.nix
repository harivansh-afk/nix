{ pkgs, ... }:
let
  port = 18434;
  proxyPort = 18435;
  httpsPort = 18443;
in
{
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda.override { cudaPackages = pkgs.cudaPackages_13_0; };
    host = "127.0.0.1";
    inherit port;
    openFirewall = false;
    loadModels = [ "qwen3:8b" ];
    environmentVariables = {
      OLLAMA_NO_CLOUD = "1";
      OLLAMA_CONTEXT_LENGTH = "8192";
      OLLAMA_NUM_PARALLEL = "2";
      OLLAMA_MAX_LOADED_MODELS = "1";
      OLLAMA_KEEP_ALIVE = "5m";
    };
  };

  systemd.services.ollama.serviceConfig = {
    MemoryMax = "16G";
    OOMScoreAdjust = 500;
  };

  services.caddy.virtualHosts."http://:${toString proxyPort}" = {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      reverse_proxy 127.0.0.1:${toString port} {
        header_up Host 127.0.0.1:${toString port}
      }
    '';
  };

  systemd.services.dictation-ai-tailscale-serve = {
    description = "Expose dictation AI over Tailscale HTTPS";
    after = [
      "ollama.service"
      "caddy.service"
      "tailscaled.service"
    ];
    wants = [
      "ollama.service"
      "caddy.service"
      "tailscaled.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "${pkgs.tailscale}/bin/tailscale wait --timeout=2m";
      ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --https=${toString httpsPort} http://127.0.0.1:${toString proxyPort}";
      ExecStop = "${pkgs.tailscale}/bin/tailscale serve --https=${toString httpsPort} off";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
