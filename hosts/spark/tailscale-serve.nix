{
  pkgs,
  lib,
  ...
}:
# Node-level Tailscale Serve / Funnel routing for spark.
#
# Each app gets its own HTTPS listen port on the host's tailnet hostname.
# We avoid sub-path mounts (--set-path) because tailscale/tailscale#12413
# (open since 2024-06) causes spurious 404s through that code path; multi-
# port serves on the same node hit a different routing layer that works.
#
# Per-app `funnel = true` flips that app's listener from tailnet-only
# `tailscale serve` to public `tailscale funnel`. Funnel is required for
# anything that must accept inbound traffic from the public internet
# (e.g. SaaS webhooks). Tailscale-Funnel-allowed hostnames have to be
# enabled in the tailnet admin console first; the CLI returns an
# "Access denied" error otherwise.
#
# We also do NOT use the upstream NixOS `services.tailscale.serve` module:
# in tailscale 1.96.5 `tailscale serve set-config --all` only accepts the
# new ServicesConfigFile schema (top-level `version` + `services.svc:<name>`)
# and rejects the legacy TCP/Web schema that module renders. The legacy
# `tailscale serve <target>` / `tailscale funnel <target>` CLI still
# configures node-level routes fine, so we drive them from a oneshot
# systemd unit instead.
let
  tsHost = "spark-ix.tail368802.ts.net";

  services = [
    {
      name = "symphony";
      port = 443;
      target = "http://127.0.0.1:4040";
      # Linear (and other SaaS) webhook delivery comes from the public
      # internet; symphony exposes POST /api/v1/triggers/linear which
      # has to be reachable there. Funnel-on, public.
      funnel = true;
    }
    {
      name = "playbook";
      port = 8443;
      target = "http://127.0.0.1:4060";
      funnel = false;
    }
  ];

  tailscale = "${pkgs.tailscale}/bin/tailscale";

  serveLine =
    {
      port,
      target,
      funnel,
      ...
    }:
    let
      verb = if funnel then "funnel" else "serve";
    in
    "${tailscale} ${verb} --bg --https=${toString port} ${lib.escapeShellArg target}";

  serveScript = pkgs.writeShellApplication {
    name = "spark-tailscale-serve";
    runtimeInputs = [ pkgs.tailscale ];
    text = ''
      set -euo pipefail

      # Wait for tailscaled to be ready so `tailscale serve` does not race
      # the daemon on boot.
      for _ in $(seq 1 30); do
        if ${tailscale} status >/dev/null 2>&1; then
          break
        fi
        sleep 1
      done

      # Reset node-level serve so this unit is the single source of truth.
      # `serve reset` clears both serve and funnel state.
      ${tailscale} serve reset

      ${lib.concatStringsSep "\n" (map serveLine services)}
    '';
  };
in
{
  # Make sure the upstream NixOS module does not also try to push a config.
  services.tailscale.serve.enable = lib.mkForce false;

  systemd.services.spark-tailscale-serve = {
    description = "Configure node-level Tailscale serve + funnel routes for ${tsHost}";
    after = [
      "tailscaled.service"
      "tailscaled-autoconnect.service"
      "tailscaled-set.service"
    ];
    wants = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${serveScript}/bin/spark-tailscale-serve";
      ExecStop = "${tailscale} serve reset";
    };
  };
}
