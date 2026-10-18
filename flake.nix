{
  description = "Hari's nix config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-macbook.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";

    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs-macbook";
    };

    googleworkspace-cli = {
      url = "github:googleworkspace/cli";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew = {
      url = "github:zhaofengli-wip/nix-homebrew";
    };

    voiceink-src = {
      url = "github:Beingpax/VoiceInk/v2.21";
      flake = false;
    };

    mattpocock-skills = {
      url = "github:mattpocock/skills";
      flake = false;
    };

    roomcast = {
      url = "git+https://git.harivan.sh/harivansh-afk/roomcast.git?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    airplay-at-the-crib = {
      url = "git+https://git.harivan.sh/harivansh-afk/airplay-at-the-crib.git?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    draw = {
      url = "git+https://git.harivan.sh/harivansh-afk/draw.git?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sharefs.url = "git+https://git.harivan.sh/harivansh-afk/sharefs.git?ref=main";

    mixbridge-web = {
      url = "git+https://git.harivan.sh/harivansh-afk/mixbridge-web.git?ref=master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hermes-agent.url = "github:NousResearch/hermes-agent";

    cc-proxy = {
      url = "git+https://git.harivan.sh/harivansh-afk/cc-proxy.git?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    devin-codex.url = "git+https://git.harivan.sh/harivansh-afk/devin-codex.git";

    neovim-nightly = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mux = {
      url = "git+https://git.harivan.sh/harivansh-afk/mux.git?ref=main";
    };

    dgx-spark = {
      url = "github:graham33/nixos-dgx-spark";
    };

    pierrejo = {
      url = "git+https://git.harivan.sh/harivansh-afk/pierrejo.git?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
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
        ./flake/packages.nix
        ./flake/tests.nix
        ./flake/user-config.nix
      ];
    };
}
