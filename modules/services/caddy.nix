{ ... }:
{
  # Internal host-based router.
  #
  # Topology:
  #   Internet ──TLS──▶ Cloudflare edge ──cloudflared tunnel──▶ spark
  #   spark ──▶ Caddy @ 127.0.0.1:80 ──▶ backend service @ 127.0.0.1:<port>
  #
  # Cloudflare terminates TLS at its edge, cloudflared delivers plain
  # HTTP here, Caddy dispatches by Host header. That means:
  #   * no ACME, no certs, no 443 listener
  #   * no public firewall ports opened for web traffic
  #   * each backend keeps binding to 127.0.0.1 only, unchanged from netty
  #
  # Per-service modules (vaultwarden.nix, forgejo.nix, …) add their own
  # `services.caddy.virtualHosts."http://<domain>"` entries pointing at
  # their loopback port. Putting `http://` in the hostname tells Caddy
  # this is a plain-HTTP site so it skips auto-HTTPS provisioning.
  services.caddy = {
    enable = true;
    globalConfig = ''
      auto_https off
    '';
  };
}
