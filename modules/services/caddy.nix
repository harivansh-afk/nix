{ lib, ... }:
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
  #   * each backend stays bound to 127.0.0.1 only

  services.caddy = {
    enable = true;
    globalConfig = ''
      auto_https off
    '';
  };

  # Helper exposed via specialArgs. Per-service modules do:
  #
  #   services.caddy.virtualHosts."http://${domain}" = loopbackVhost port;
  #
  # Kept as a plain value-producing function (NOT a module) so callers
  # can use it under `config` without tripping an imports-time
  # infinite-recursion on `_module.args`.
  _module.args.loopbackVhost = port: {
    listenAddresses = [ "127.0.0.1" ];
    extraConfig = ''
      reverse_proxy 127.0.0.1:${toString port}
    '';
  };
}
