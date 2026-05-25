{
  description = "Hari's nix config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-nushell.url = "github:NixOS/nixpkgs/01fbdeef22b76df85ea168fbfe1bfd9e63681b30";
    flake-parts.url = "github:hercules-ci/flake-parts";
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
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

    neovim-nightly = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dgx-spark = {
      url = "github:graham33/nixos-dgx-spark";
    };

    pi-mono = {
      url = "github:lukasl-dev/pi-mono.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pierrejo = {
      url = "git+https://git.harivan.sh/harivansh-afk/pierrejo.git?rev=2c9ca6df99aed094802b4d6989e8d67457d61dd0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
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

    devin-cli = {
      url = "github:charliemeyer2000/devin-cli-overlay";
    };

    codex-cli = {
      url = "github:sadjow/codex-cli-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Symphony ships its own NixOS deployment artifacts: the run-nix
    # entrypoint, the encrypted env file at secrets/symphony.env, and
    # eventually a NixOS module. Pinning it here means an admin can
    # `nix flake update symphony` and `nixos-rebuild switch` to roll
    # forward both the binary and the encrypted env atomically.
    symphony = {
      url = "github:indexable-inc/symphony";
      flake = false;
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ./flake/args.nix
        ./flake/devshell.nix
        ./flake/hosts.nix
        ./flake/nixos.nix
      ];
    };
}
