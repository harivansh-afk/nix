{
  description = "Rathi's macOS nix-darwin + NixOS + Home Manager config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

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

  outputs = inputs @ {
    self,
    nixpkgs,
    nix-darwin,
    home-manager,
    claudeCode,
    nix-homebrew,
    ...
  }: let
    darwinSystem = "aarch64-darwin";
    linuxSystem = "x86_64-linux";
    username = "rathi";
    darwinConfigName = "darwin";
    darwinMachineHostname = "hari-macbook-pro";
    linuxConfigName = "linux";
    linuxHostname = "rathi-vps";
    darwinPkgs = import nixpkgs {system = darwinSystem;};
    linuxPkgs = import nixpkgs {
      system = linuxSystem;
      config.allowUnfree = true;
    };
  in {
    formatter.${darwinSystem} = darwinPkgs.alejandra;
    formatter.${linuxSystem} = linuxPkgs.alejandra;

    darwinConfigurations.${darwinConfigName} = nix-darwin.lib.darwinSystem {
      system = darwinSystem;
      specialArgs = {
        inherit inputs self username;
        hostname = darwinMachineHostname;
      };
      modules = [
        ./hosts/${darwinConfigName}
        home-manager.darwinModules.home-manager
        nix-homebrew.darwinModules.nix-homebrew
        {
          users.users.${username}.home = "/Users/${username}";

          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = {
            inherit inputs self username;
            hostname = darwinMachineHostname;
          };
          home-manager.backupFileExtension = "hm-bak";
          home-manager.users.${username} = import ./home;

          nix-homebrew = {
            enable = true;
            enableRosetta = true;
            user = username;
            autoMigrate = true;
          };
        }
      ];
    };

    nixosConfigurations.${linuxConfigName} = nixpkgs.lib.nixosSystem {
      system = linuxSystem;
      specialArgs = {
        inherit inputs self username;
        hostname = linuxHostname;
      };
      modules = [
        inputs.disko.nixosModules.disko
        ./hosts/${linuxConfigName}/configuration.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = {
            inherit inputs self username;
            hostname = linuxHostname;
          };
          home-manager.backupFileExtension = "hm-bak";
          home-manager.users.${username} = import ./home/linux.nix;
        }
      ];
    };

    # Standalone Home Manager config (fallback for non-NixOS Linux)
    homeConfigurations.${linuxConfigName} = home-manager.lib.homeManagerConfiguration {
      pkgs = linuxPkgs;
      extraSpecialArgs = {
        inherit inputs self username;
        hostname = linuxConfigName;
      };
      modules = [
        ./hosts/${linuxConfigName}
      ];
    };
  };
}
