{
  inputs,
  self,
  hostname,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.dgx-spark.nixosModules.dgx-spark
    inputs.lanzaboote.nixosModules.lanzaboote
    ../../modules/common.nix
    inputs.sops-nix.nixosModules.sops
    ../../modules/security/sops.nix
    ../../modules/users/nixos.nix
    ./kernel-hardening.nix
    ./services/caddy.nix
    ./services/cloudflared.nix
    ./services/forgejo
    ./services/inference.nix
    ./services/knowledge-base.nix
    ./services/kb-ingest.nix
    ./services/kb-ingestion.nix
    ./services/nap.nix
    ./services/mosh.nix
    ./services/muxd.nix
    ./services/whisper.nix
    ./services/vaultwarden.nix
    ./services/website-counter.nix
    ./services/website.nix
    ./hardware.nix
    ./networking.nix
    ./omp.nix
    ./users.nix
  ]
  ++ lib.optional (builtins.pathExists ./hardware-configuration.nix) ./hardware-configuration.nix;

  networking.hostName = hostname;

  boot = {
    initrd.systemd.enable = true;
    lanzaboote = {
      allowUnsigned = false;
      configurationLimit = 4;
      enable = true;
      pkiBundle = "/var/lib/sbctl";
    };
    loader.systemd-boot.editor = false;
  };

  security.tpm2.enable = true;

  nixpkgs.config.cudaCapabilities = [ "12.1" ];

  nix.settings = {
    accept-flake-config = true;
    experimental-features = [
      "ca-derivations"
      "fetch-tree"
      "flakes"
      "nix-command"
    ];
  };

  environment.systemPackages = with pkgs; [
    clang
  ];

  # System-wide git stall timeout (/etc/gitconfig). git has no default network
  # timeout: a flake-input fetch over https://git.harivan.sh once stalled on a
  # dead connection and hung two CI jobs (and the deploy queue) for hours.
  # Abort any HTTP transfer that stays below 1 KB/s for 60 consecutive seconds.
  # Covers root's nix fetches (sudo nixos-rebuild) and the gitea-runner user,
  # which per-user gitconfig and runner env vars (stripped by sudo) do not.
  programs.git = {
    enable = true;
    config = {
      http = {
        lowSpeedLimit = 1000;
        lowSpeedTime = 60;
      };
    };
  };

  # nh (Nix Helper) drives `just switch`/`switch-spark`; enable periodic GC via
  # `nh clean` (keep last 5 generations and anything newer than 7 days).
  programs.nh = {
    enable = true;
    clean = {
      enable = true;
      extraArgs = "--keep-since 7d --keep 5";
    };
  };

  system.configurationRevision = self.rev or self.dirtyRev or null;

  system.stateVersion = "25.11";

  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      zlib
      openssl
      curl
      glib
      libgcc
    ];
  };
}
