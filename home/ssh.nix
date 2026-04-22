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
        hostname = "100.73.113.83";
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
