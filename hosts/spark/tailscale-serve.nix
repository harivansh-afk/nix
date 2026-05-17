{
  pkgs,
  lib,
  ...
}:
# Node-level Tailscale Serve routing for spark.
#
# Each app gets its own HTTPS listen port on the host's tailnet hostname.
# We avoid sub-path mounts (--set-path) because tailscale/tailscale#12413
# (open since 2024-06) causes spurious 404s through that code path; multi-
# port serves on the same node hit a different routing layer that works.
#
# We also do NOT use the upstream NixOS `services.tailscale.serve` module:
# in tailscale 1.96.5 `tailscale serve set-config --all` only accepts the
# new ServicesConfigFile schema (top-level `version` + `services.svc:<name>`)
# and rejects the legacy TCP/Web schema that module renders. The legacy
# `tailscale serve <target>` CLI still configures node-level serve fine, so
# we drive it from a oneshot systemd unit instead.
let
  tsHost = "spark-ix.tail368802.ts.net";

  services = [
    {
      name = "symphony";
      port = 443;
      target = "http://127.0.0.1:4040";
    }
    {
      name = "playbook";
      port = 8443;
      target = "http://127.0.0.1:4060";
    }
  ];

  tailscale = "${pkgs.tailscale}/bin/tailscale";

  serveLine =
    { port, target, ... }:
    "${tailscale} serve --bg --https=${toString port} ${lib.escapeShellArg target}";

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
      ${tailscale} serve reset

      ${lib.concatStringsSep "\n" (map serveLine services)}
    '';
  };
in
{
  # Make sure the upstream NixOS module does not also try to push a config.
  services.tailscale.serve.enable = lib.mkForce false;

  systemd.services.spark-tailscale-serve = {
    description = "Configure node-level Tailscale Serve routes for ${tsHost}";
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
