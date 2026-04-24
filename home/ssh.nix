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
      };

    }
    // ixMatchBlocks;
  };
}
