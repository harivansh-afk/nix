{ ... }:
{
  # Mosh: UDP-based terminal with local echo and predictive display.
  # Pairs well with Tailscale (works over the WireGuard tunnel) and with
  # direct LAN SSH at home. Does not work over the Cloudflare tunnel
  # because that ingress is TCP-only; friends connecting via
  # spark.harivan.sh stay on plain SSH, which is fine for that path.
  #
  # Enabling this installs mosh-server and opens UDP 60000-61000 in the
  # firewall. The bootstrap still uses the existing OpenSSH config from
  # hosts/spark/users.nix, so authorized keys and other SSH settings are
  # inherited unchanged.
  programs.mosh.enable = true;
}
