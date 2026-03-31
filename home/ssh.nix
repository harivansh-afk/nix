{ ... }:
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    includes = [
      "/Users/rathi/.config/colima/ssh_config"
    ];

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

      "agentcomputer.ai" = {
        hostname = "ssh.agentcomputer.ai";
        port = 443;
        user = "agentcomputer";
        identityFile = "~/.ssh/id_ed25519";
        identitiesOnly = true;
        serverAliveInterval = 30;
        serverAliveCountMax = 4;
      };

      "*" = {
        setEnv = {
          TERM = "xterm-256color";
        };
      };
    };
  };
}
