_: {
  programs.mosh = {
    enable = true;
    openFirewall = false;
  };

  networking.firewall.interfaces.tailscale0.allowedUDPPortRanges = [
    {
      from = 60000;
      to = 61000;
    }
  ];
}
