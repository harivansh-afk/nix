# Eval tests over the host configurations, in the spirit of index's
# tests/default.nix: cheap assertions that force-evaluate the rendered
# config so policy violations and darwin module errors fail
# `nix flake check` (and therefore CI) instead of the next rebuild.
#
# Every invariant is a lib.assertMsg, so a violation names itself; the
# check derivations are writeText shells whose content forces the eval.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      spark = self.nixosConfigurations.spark.config;

      # Ports the repo policy bans for self-hosted backends
      # (well-known/high-value; see CLAUDE.md project preferences).
      bannedPorts = [
        3000
        8000
        8080
      ];

      # Every port Caddy reverse-proxies to, recovered from the rendered
      # vhost extraConfig (loopbackVhost emits "reverse_proxy 127.0.0.1:N").
      proxiedPorts = lib.concatMap (
        vh:
        let
          m = builtins.match ".*reverse_proxy 127\\.0\\.0\\.1:([0-9]+).*" vh.extraConfig;
        in
        lib.optional (m != null) (lib.toInt (builtins.head m))
      ) (lib.attrValues spark.services.caddy.virtualHosts);

      invariants = [
        (lib.assertMsg (proxiedPorts != [ ])
          "spark: expected at least one caddy reverse_proxy backend; the port-extraction regex may have rotted"
        )
        (lib.assertMsg (lib.all (p: !(lib.elem p bannedPorts)) proxiedPorts)
          "spark: a caddy backend sits on a banned well-known port (${
            lib.concatMapStringsSep ", " toString proxiedPorts
          })"
        )
        (lib.assertMsg (lib.all (vh: vh.listenAddresses == [ "127.0.0.1" ]) (
          lib.attrValues spark.services.caddy.virtualHosts
        )) "spark: every caddy virtualHost must bind loopback only")
        (lib.assertMsg (
          spark.services.vaultwarden.config.ROCKET_ADDRESS == "127.0.0.1"
        ) "spark: vaultwarden must bind loopback")
        (lib.assertMsg (lib.all (t: t.default == "http://127.0.0.1:80") (
          lib.attrValues spark.services.cloudflared.tunnels
        )) "spark: cloudflared tunnels must default to the loopback caddy")
        (lib.assertMsg (
          spark.services.forgejo.settings.server.ROOT_URL == "https://git.harivan.sh/"
        ) "spark: forgejo ROOT_URL drifted from git.harivan.sh")
        (lib.assertMsg (
          spark.networking.firewall.enable && spark.networking.firewall.allowedTCPPorts == [ 22 ]
        ) "spark: firewall must be enabled with only ssh open; backends are reached via the tunnel")
      ];
    in
    {
      checks = {
        spark-invariants = pkgs.writeText "spark-invariants" (builtins.toJSON (lib.all lib.id invariants));
        # Full eval of the darwin system closure. `nix flake check` does not
        # know the darwinConfigurations output schema and skips it entirely,
        # so without this a darwin-only module error merges green and only
        # surfaces on the next darwin-rebuild ("chore: fix darwin" commits).
        # Forcing the toplevel drvPath is the eval; the string context is
        # discarded on purpose so the darwin closure does not become a build
        # input of this check (it cannot build on the linux runner, and does
        # not need to: a failed eval already fails the check).
        eval-macbook = pkgs.writeText "eval-macbook" (
          builtins.unsafeDiscardStringContext self.darwinConfigurations.macbook.system.drvPath
        );
      };
    };
}
