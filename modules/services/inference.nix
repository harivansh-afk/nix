{ pkgs, ... }:
{
  services.ollama = {
    enable = true;
    host = "127.0.0.1";
    port = 11434;
    package = pkgs.ollama-cuda;
  };

  systemd.services.ollama.environment.OLLAMA_CONTEXT_LENGTH = "8192";
}
