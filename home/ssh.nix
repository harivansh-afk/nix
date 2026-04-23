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

      spark = {
        # Resolved via Tailscale MagicDNS so it follows renames / IP changes.
        hostname = "spark";
        user = "rathi";
        identityFile = "~/.ssh/id_ed25519";
        identitiesOnly = true;
      };

    };
  };
}
