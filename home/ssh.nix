{ ... }:
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    matchBlocks = {
      aurelius = {
        hostname = "100.71.160.102";
        user = "nixos";
        identityFile = "~/.ssh/id_ed25519";
      };

      netty = {
        hostname = "152.53.195.59";
        user = "rathi";
        identityFile = "~/.ssh/netty";
        identitiesOnly = true;
      };

      spark = {
        # Resolved via Tailscale MagicDNS so it follows renames / IP changes.
        hostname = "spark";
        user = "rathi";
        identityFile = "~/.ssh/id_ed25519";
        identitiesOnly = true;
      };

      "*" = {
        setEnv = {
          TERM = "xterm-256color";
        };
      };
    };
  };
}
