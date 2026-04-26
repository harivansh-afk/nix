{ ... }:
let
  ixHostOptions = {
    addKeysToAgent = "yes";
    forwardAgent = true;
    identitiesOnly = true;
    port = 9999;
    user = "hari";
  };

  ixHosts = {
    hil-compute-1 = "15.204.111.75";
    hil-compute-2 = "15.204.105.165";
    hil-stor-1 = "15.204.106.118";
    vin-compute-1 = "40.160.30.136";
    vin-compute-2 = "40.160.64.85";
    vin-stor-1 = "15.204.241.32";
  };

  ixMatchBlocks = builtins.mapAttrs (_: hostname: ixHostOptions // { inherit hostname; }) ixHosts;
in
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
        # Forward the local agent so commands on spark (git push, ssh into
        # other hosts, ix tooling) can reuse the Mac's keys without copying
        # private material to the box.
        forwardAgent = true;
        # Multiplex connections: first session pays the ~350ms handshake,
        # subsequent ssh / scp / rsync invocations reuse the socket and
        # connect in a few ms. Matters a lot for just switch-spark,
        # agent-history sync, and any tool that fires multiple sessions.
        controlMaster = "auto";
        controlPath = "~/.ssh/sockets/%r@%h:%p";
        controlPersist = "10m";
        serverAliveInterval = 60;
        serverAliveCountMax = 3;
      };

    }
    // ixMatchBlocks;
  };
}
