{
  config,
  ...
}:
let
  tunnelId = "64bce32c-6613-459c-bb68-262d73e1b78f";
in
{
  services.cloudflared = {
    enable = true;
    tunnels.${tunnelId} = {
      credentialsFile = config.sops.secrets."cloudflared.json".path;
      default = "http://127.0.0.1:80";
    };
  };

  # Defense-in-depth against the boot-time DNS race that took the tunnel (and
  # every service behind it) offline for ~4h on 2026-06-05. cloudflared started
  # before a resolver was answering, its edge-discovery SRV lookup failed with
  # "connection refused", it burned through the default 5-restarts-in-10s limit
  # within ~1s, and systemd then permanently gave up ("start request repeated
  # too quickly"). The local stub resolver (services.resolved) is the actual
  # fix; these settings ensure the tunnel also waits for DNS, backs off between
  # attempts, and never stops retrying on a transient failure.
  systemd.services."cloudflared-tunnel-${tunnelId}" = {
    after = [ "nss-lookup.target" ];
    wants = [ "nss-lookup.target" ];
    serviceConfig = {
      Restart = "always";
      RestartSec = "15s";
    };
    startLimitIntervalSec = 0;
  };
}
