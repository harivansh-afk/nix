{
  description = "Hari's nix config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    # Determinate Nix owns /etc/nix/nix.conf, the daemon, and the installed
    # Nix version. Do NOT set inputs.nixpkgs.follows here; Determinate
    # recommends against it.
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

    claudeCode = {
      url = "github:sadjow/claude-code-nix";
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
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ./flake/args.nix
        ./flake/devshell.nix
        ./flake/macbook.nix
      ];
    };
}
