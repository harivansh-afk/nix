{
  pkgs,
  lib,
  ...
}:
# Node-level Tailscale Serve routing for spark.
#
# We deliberately do NOT use `services.tailscale.serve` here. In tailscale
# 1.96.5, `tailscale serve set-config --all` only accepts the new
# `ServicesConfigFile` schema (top-level `version` + `services.svc:<name>`).
# The legacy node-serve schema (top-level `TCP` / `Web`) that NixOS' upstream
# module hands it gets rejected with:
#
#   json: cannot unmarshal JSON string into Go conffile.ServicesConfigFile:
#   unknown object member name "TCP"
#
# The legacy `tailscale serve <target>` CLI still works for node-level serve
# (it writes directly to tailscaled's local state), so we use it from a
# oneshot systemd unit instead.
let
  tsHost = "spark-ix.tail368802.ts.net";

  # URL path -> upstream URL on loopback. The root entry must use path "/";
  # everything else is mounted via `--set-path`.
  routes = [
    {
      path = "/";
      target = "http://127.0.0.1:4040";
    } # symphony
    {
      path = "/playbooks";
      target = "http://127.0.0.1:4060";
    } # playbook UI
  ];

  tailscale = "${pkgs.tailscale}/bin/tailscale";

  serveLine =
    { path, target }:
    let
      pathFlag = lib.optionalString (path != "/") " --set-path=${lib.escapeShellArg path}";
    in
    "${tailscale} serve --bg --https=443${pathFlag} ${lib.escapeShellArg target}";

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

      ${lib.concatStringsSep "\n" (map serveLine routes)}
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
