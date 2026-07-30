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
        (lib.assertMsg (
          spark.users.users.root.hashedPassword == "!"
          && spark.users.users.root.openssh.authorizedKeys.keys == [ ]
        ) "spark: root must have no password or authorized ssh keys")
        (lib.assertMsg spark.security.sudo.wheelNeedsPassword "spark: wheel must authenticate before sudo")
        (lib.assertMsg (
          spark.security.apparmor.enable
          && spark.security.audit.enable
          && spark.security.auditd.enable
          && spark.security.lockKernelModules
          && spark.security.protectKernelImage
        ) "spark: mandatory access, audit, and kernel mutation protections must stay enabled")
        (lib.assertMsg (
          spark.boot.kexec.enable == false
          && spark.boot.kernel.sysctl."kernel.unprivileged_bpf_disabled" == 1
          && spark.boot.kernel.sysctl."dev.tty.ldisc_autoload" == 0
          && spark.boot.kernel.sysctl."fs.suid_dumpable" == 0
        ) "spark: kernel mutation and information-exposure controls drifted")
        (lib.assertMsg (lib.all (parameter: lib.elem parameter spark.boot.kernelParams) [
          "hardened_usercopy=1"
          "init_on_alloc=1"
          "iommu.passthrough=0"
          "iommu.strict=1"
          "mitigations=auto,nosmt"
          "proc_mem.force_override=never"
          "slab_nomerge"
        ]) "spark: required kernel hardening parameters are missing")
        (lib.assertMsg (
          spark.systemd.sleep.settings.Sleep.AllowSuspend == false
          && spark.systemd.sleep.settings.Sleep.AllowHibernation == false
          && spark.systemd.services.systemd-coredump.enable == false
        ) "spark: sleep states and core dumps must stay disabled")
        (lib.assertMsg (
          spark.boot.lanzaboote.enable
          && !spark.boot.lanzaboote.allowUnsigned
          && spark.boot.lanzaboote.configurationLimit == 4
          && !spark.boot.loader.systemd-boot.enable
          && !spark.boot.loader.systemd-boot.editor
        ) "spark: lanzaboote must install signed UKIs with no boot editor")
        (lib.assertMsg (
          spark.boot.initrd.systemd.enable && spark.security.tpm2.enable
        ) "spark: verified boot requires the systemd initrd and TPM2 userspace")
        (lib.assertMsg (
          spark.disko.devices.disk.main.content.partitions.root.content.type == "luks"
          && spark.disko.devices.disk.main.content.partitions.root.content.name == "cryptroot"
          &&
            spark.disko.devices.disk.main.content.partitions.root.content.settings.crypttabExtraOpts
            == [ "fido2-device=auto" ]
          && !(spark.disko.devices.disk.main.content.partitions ? swap)
        ) "spark: root must use FIDO2-capable LUKS2 with no plaintext swap")
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
