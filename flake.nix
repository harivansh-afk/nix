{
  description = "Hari's nix config";

  inputs = {
    # Primary package set for both hosts (macbook follows unstable too, so the
    # two machines share one package universe; see CLAUDE.md project prefs).
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # Separate nixpkgs pin used only for nushell on darwin: the nushell test
    # suite hits EPERM failures in the darwin sandbox on newer revs, and a
    # dedicated pin avoids that without invalidating the spark NVIDIA kernel
    # hash. Drop the pin (system/common.nix overlay goes with it) once
    # nushell builds clean from the main nixpkgs on darwin.
    nixpkgs-nushell.url = "github:NixOS/nixpkgs/01fbdeef22b76df85ea168fbfe1bfd9e63681b30";

    # Module system for the flake's own outputs (everything under flake/).
    flake-parts.url = "github:hercules-ci/flake-parts";

    # Manages the Nix installation, daemon, and /etc/nix/nix.conf. On darwin,
    # nix settings go through determinateNix.customSettings, not nix.settings.
    # No nixpkgs follows: it ships its own pinned determinate-nixd.
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";

    # macbook system layer.
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # `gws` CLI, consumed in packages.nix extras.
    googleworkspace-cli = {
      url = "github:googleworkspace/cli";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # OpenSpec CLI, consumed in packages.nix extras.
    openspec = {
      url = "github:Fission-AI/OpenSpec";
    };

    # Declarative Homebrew (taps, casks) on macbook only.
    nix-homebrew = {
      url = "github:zhaofengli-wip/nix-homebrew";
    };

    # VoiceInk dictation app, built from source on macbook (GPLv3). The
    # prebuilt cask is the paid path; building from source with `make local`
    # (ad-hoc signing, no Apple Developer account) is the free path. Pinned
    # source only: it is an Xcode app, not a flake. See modules/apps/voiceink.nix.
    voiceink-src = {
      url = "github:Beingpax/VoiceInk";
      flake = false;
    };

    # Neovim nightly overlay, applied on darwin only: there is no binary
    # cache for aarch64-linux, so spark stays on the nixpkgs neovim.
    neovim-nightly = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Upstream NixOS module for the DGX Spark hardware. Deliberately no
    # nixpkgs follows: upstream pins a known-good revision for the NVIDIA
    # kernel build, and overriding it invalidates that hash.
    dgx-spark = {
      url = "github:graham33/nixos-dgx-spark";
    };

    # pi agent NixOS module (hosts/spark/pi.nix).
    pi-mono = {
      url = "github:lukasl-dev/pi-mono.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # indexable-inc monorepo, consumed as a source tree for the pi-harness
    # extension (hosts/spark/pi.nix).
    index = {
      url = "github:indexable-inc/index";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Pierre-themed Forgejo frontend (modules/services/forgejo). Hosted on
    # this same Forgejo instance, so flake updates need read access to it.
    pierrejo = {
      url = "git+https://git.harivan.sh/harivansh-afk/pierrejo.git?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative partitioning for spark; paired with nixos-anywhere for
    # from-scratch provisioning.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Remote installer used to (re)provision spark over SSH.
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets: every secret lives encrypted in secrets/ and is declared in
    # secrets/registry.nix; modules/security/sops.nix does the wiring.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Cloudflare DNS as nix (terraform/cloudflare, flake/cloudflare.nix),
    # driven by `just dns-plan` / `just dns-apply`.
    terranix = {
      url = "github:terranix/terranix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ./flake/args.nix
        ./flake/checks.nix
        ./flake/cloudflare.nix
        ./flake/devshell.nix
        ./flake/hosts.nix
        ./flake/nixos.nix
        ./flake/tests.nix
        ./flake/user-config.nix
      ];
    };
}
