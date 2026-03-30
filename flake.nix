{
  description = "Rathi's macOS nix-darwin + NixOS + Home Manager config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

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

    agentcomputer-cli = {
      url = "path:/Users/rathi/Documents/GitHub/companion/agentcomputer/apps/cli";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    openspec = {
      url = "github:Fission-AI/OpenSpec";
    };

    nix-homebrew = {
      url = "github:zhaofengli-wip/nix-homebrew";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      flake-parts,
      nixpkgs,
      nix-darwin,
      home-manager,
      nix-homebrew,
      ...
    }:
    let
      username = "rathi";
      hosts = import ./lib/hosts.nix { inherit username; };

      mkPkgs =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

      mkHomeManagerModule =
        host:
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = {
            inherit inputs self username;
            hostname = host.hostname;
          };
          home-manager.backupFileExtension = "hm-bak";
          home-manager.users.${username} = import host.homeModule;
        };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        hosts.darwin.system
        hosts.netty.system
      ];

      imports = [
        ./modules/devshells.nix
      ];

      flake = {
        darwinConfigurations.${hosts.darwin.name} = nix-darwin.lib.darwinSystem {
          system = hosts.darwin.system;
          specialArgs = {
            inherit inputs self username;
            hostname = hosts.darwin.hostname;
          };
          modules = [
            ./hosts/${hosts.darwin.name}
            home-manager.darwinModules.home-manager
            nix-homebrew.darwinModules.nix-homebrew
            {
              users.users.${username}.home = hosts.darwin.homeDirectory;

              nix-homebrew = {
                enable = true;
                enableRosetta = true;
                user = username;
                autoMigrate = true;
              };
            }
            (mkHomeManagerModule hosts.darwin)
          ];
        };

        nixosConfigurations.${hosts.netty.name} = nixpkgs.lib.nixosSystem {
          system = hosts.netty.system;
          specialArgs = {
            inherit inputs self username;
            hostname = hosts.netty.hostname;
          };
          modules = [
            inputs.disko.nixosModules.disko
            ./hosts/${hosts.netty.name}/configuration.nix
            home-manager.nixosModules.home-manager
            (mkHomeManagerModule hosts.netty)
          ];
        };

        homeConfigurations.${hosts.netty.name} = home-manager.lib.homeManagerConfiguration {
          pkgs = mkPkgs hosts.netty.system;
          extraSpecialArgs = {
            inherit inputs self username;
            hostname = hosts.netty.hostname;
          };
          modules = [
            hosts.netty.standaloneHomeModule
          ];
        };
      };
    };
}
