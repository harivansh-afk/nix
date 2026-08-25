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

    # Matt Pocock's agent skills (engineering + productivity buckets). Linked
    # into ~/.agents/skills by the user activation script; bump with
    # `nix flake update mattpocock-skills`.
    mattpocock-skills = {
      url = "github:mattpocock/skills";
      flake = false;
    };

    # Neovim nightly overlay, applied on darwin only: there is no binary
    # cache for aarch64-linux, so spark stays on the nixpkgs neovim.
    neovim-nightly = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hermes-agent = {
      url = "github:NousResearch/hermes-agent/v2026.7.20";
    };

    # mux: native terminal multiplexer. This flake provides the muxd session
    # daemon package + a NixOS module; spark runs muxd so panes on the Mac app
    # can live here over QUIC. No nixpkgs follows: the flake pins a nixpkgs
    # carrying zig 0.16, which ghostty-vt's build needs, and overriding it can
    # break that build (same reasoning as dgx-spark).
    mux = {
      url = "git+https://git.harivan.sh/harivansh-afk/mux.git?ref=main";
    };

    # Upstream NixOS module for the DGX Spark hardware. Deliberately no
    # nixpkgs follows: upstream pins a known-good revision for the NVIDIA
    # kernel build, and overriding it invalidates that hash.
    dgx-spark = {
      url = "github:graham33/nixos-dgx-spark";
    };

    # Pierre-themed Forgejo frontend (modules/services/forgejo). Hosted on
    # this same Forgejo instance, so flake updates need read access to it.
    pierrejo = {
      url = "git+https://git.harivan.sh/harivansh-afk/pierrejo.git?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Rust toolchains by date, for packages needing the ix repo's pinned
    # nightly (pkgs/jj-ix). Consumed via lib.mkRustBin, not as an overlay,
    # so the main package set stays untouched.
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ix monorepo source for pkgs/jj-ix (the patched jj with the ix store
    # backend - the client for the jj-native forge at forge.ix.dev). Pinned
    # to the archived GitHub mirror's FINAL commit (2026-08-12): the forge
    # itself is not nix-fetchable, so bumping past this pin needs a tree
    # exported from the forge (or a fetchable public mirror, ix ADR 0006).
    # Fetching needs `access-tokens = github.com=...` in nix.conf on the
    # building machine (the repo is org-internal).
    ix-src = {
      url = "github:indexable-inc/ix/f72060016d74211e72793f295d3b8697d1994a3d";
      flake = false;
    };

    # Declarative partitioning for spark; paired with nixos-anywhere for
    # from-scratch provisioning.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.1.0";
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
        ./flake/ix.nix
        ./flake/nixos.nix
        ./flake/omp.nix
        ./flake/portable.nix
        ./flake/scripts.nix
        ./flake/tests.nix
        ./flake/user-config.nix
      ];
    };
}
