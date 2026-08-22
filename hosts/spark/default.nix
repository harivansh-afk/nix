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
    ../../system/common.nix
    ../../system/packages.nix
    inputs.sops-nix.nixosModules.sops
    ../../modules/security/sops.nix
    ../../modules/users/nixos.nix
    ../../modules/services/browser-use.nix
    ../../modules/services/caddy.nix
    ../../modules/services/cloudflared.nix
    ../../modules/services/delta.nix
    ../../modules/services/forgejo
    ../../modules/services/inference.nix
    ../../modules/services/hermes.nix
    ../../modules/services/knowledge-base.nix
    ../../modules/services/kb-ingest.nix
    ../../modules/services/kb-ingestion.nix
    ../../modules/services/kb-graph.nix
    ../../modules/services/kb-graph-query.nix
    ../../modules/services/kb-finance.nix
    ../../modules/services/hermes-loops.nix
    ../../modules/services/mosh.nix
    ../../modules/services/mux-restore.nix
    ../../modules/services/muxd.nix
    ../../modules/services/whisper.nix
    ../../modules/services/vaultwarden.nix
    ../../modules/services/website-counter.nix
    ../../modules/services/website.nix
    ./hardware.nix
    ./networking.nix
    ./omp.nix
    ./users.nix
  ]
  ++ lib.optional (builtins.pathExists ./hardware-configuration.nix) ./hardware-configuration.nix;

  networking.hostName = hostname;

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

  boot.specialFileSystems."/proc".options = [ "hidepid=invisible" ];

  boot.kernel.sysctl = {
    "kernel.yama.ptrace_scope" = 2;
    "kernel.dmesg_restrict" = 1;
    "kernel.kptr_restrict" = 2;
  };

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
