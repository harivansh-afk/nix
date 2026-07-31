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
          spark.networking.firewall.enable
          && spark.networking.firewall.allowedTCPPorts == [ ]
          && spark.networking.firewall.allowedUDPPortRanges == [ ]
        ) "spark: the global firewall must expose no TCP or UDP ports")
        (lib.assertMsg (
          spark.services.openssh.enable
          && !spark.services.openssh.openFirewall
          && spark.services.openssh.settings.PasswordAuthentication == false
          && spark.services.openssh.settings.KbdInteractiveAuthentication == false
          && spark.services.openssh.settings.PermitRootLogin == "no"
        ) "spark: openssh must require keys, deny root, and leave the global firewall closed")
        (lib.assertMsg (
          !spark.programs.mosh.openFirewall
        ) "spark: mosh must rely on the tailscale trust boundary")
        # Forgejo's git user is the one non-human account sshd admits, and the
        # two ways that can go wrong are opposite: drop it and every ssh push
        # breaks (silently, until someone tries), or add it bare and a service
        # account becomes reachable from anywhere sshd is. Both fail here.
        (
          let
            allow = spark.services.openssh.settings.AllowUsers;
            gitOrigins = lib.filter (u: lib.hasPrefix "git@" u) allow;
          in
          lib.assertMsg ((spark.services.forgejo.enable -> gitOrigins != [ ]) && !(lib.elem "git" allow))
            "spark: forgejo's git user must be in AllowUsers and always source-qualified (git@loopback or git@tailnet), never a bare \"git\""
        )
        (lib.assertMsg (
          spark.users.users.root.hashedPassword == "!"
          && spark.users.users.root.openssh.authorizedKeys.keys == [ ]
        ) "spark: root must have no password or authorized ssh keys")
        (lib.assertMsg spark.security.sudo.wheelNeedsPassword "spark: wheel must authenticate before sudo")
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
