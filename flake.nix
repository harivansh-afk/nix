{
  description = "Hari's nix config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # nushell's tests fail in the darwin sandbox on newer nixpkgs; pinned separately so the spark kernel hash stays put.
    nixpkgs-nushell.url = "github:NixOS/nixpkgs/01fbdeef22b76df85ea168fbfe1bfd9e63681b30";

    flake-parts.url = "github:hercules-ci/flake-parts";

    # Owns the nix install and nix.conf; darwin settings go through determinateNix.customSettings.
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    googleworkspace-cli = {
      url = "github:googleworkspace/cli";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    openspec = {
      url = "github:Fission-AI/OpenSpec";
    };

    nix-homebrew = {
      url = "github:zhaofengli-wip/nix-homebrew";
    };

    # Xcode app, built from source in hosts/macbook/voiceink.
    voiceink-src = {
      url = "github:Beingpax/VoiceInk";
      flake = false;
    };

    # Agent skills, linked into ~/.agents/skills by the user activation.
    mattpocock-skills = {
      url = "github:mattpocock/skills";
      flake = false;
    };

    hermes-agent.url = "github:NousResearch/hermes-agent";

    # Darwin only: no aarch64-linux cache, spark keeps nixpkgs neovim.
    neovim-nightly = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # No nixpkgs follows: mux pins the zig 0.16 nixpkgs ghostty-vt needs.
    mux = {
      url = "git+https://git.harivan.sh/harivansh-afk/mux.git?ref=main";
    };

    # No nixpkgs follows: upstream pins the revision its NVIDIA kernel build was tested on.
    dgx-spark = {
      url = "github:graham33/nixos-dgx-spark";
    };

    # Forgejo frontend theme, hosted on that same Forgejo (flake updates need read access).
    pierrejo = {
      url = "git+https://git.harivan.sh/harivansh-afk/pierrejo.git?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Dated rust toolchains for pkgs/jj-ix, consumed via lib.mkRustBin, not as an overlay.
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ix monorepo for pkgs/jj-ix, pinned to the archived mirror's final commit; fetching needs a github access-token in nix.conf.
    ix-src = {
      url = "github:indexable-inc/ix/f72060016d74211e72793f295d3b8697d1994a3d";
      flake = false;
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Cloudflare DNS as nix (terraform/cloudflare, flake/cloudflare.nix); just dns-plan / dns-apply.
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
        ./flake/omp.nix
        ./flake/packages.nix
        ./flake/tests.nix
        ./flake/user-config.nix
      ];
    };
}
