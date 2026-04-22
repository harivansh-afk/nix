{ ... }:
{
  networking.networkmanager.enable = true;

  services.tailscale = {
    enable = true;
    # "server" lets this host act as a subnet router / exit node later
    # without needing another rebuild. No routes are advertised until
    # `tailscale up --advertise-routes=...` is run imperatively.
    useRoutingFeatures = "server";
    openFirewall = true;
  };

  networking.firewall = {
    enable = true;
    # `podman+` is trusted by the upstream dgx-spark module already so
    # containers can reach host services. tailscale0 is trusted so LAN
    # services addressed over the tailnet aren't firewalled.
    trustedInterfaces = [ "tailscale0" ];
  };

  # Better memory behaviour than the 2G swap partition under load.
  zramSwap.enable = true;
}
