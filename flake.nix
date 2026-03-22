{
  description = "Rathi's macOS nix-darwin + Linux Home Manager config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:LnL7/nix-darwin/master";
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

    nix-homebrew = {
      url = "github:zhaofengli-wip/nix-homebrew";
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
    darwinHostname = "hari-macbook-pro";
    linuxHostname = "workstation";
    darwinPkgs = import nixpkgs {system = darwinSystem;};
    linuxPkgs = import nixpkgs {
      system = linuxSystem;
      config.allowUnfree = true;
    };
  in {
    formatter.${darwinSystem} = darwinPkgs.alejandra;
    formatter.${linuxSystem} = linuxPkgs.alejandra;

    darwinConfigurations.${darwinHostname} = nix-darwin.lib.darwinSystem {
      system = darwinSystem;
      specialArgs = {
        inherit inputs self username;
        hostname = darwinHostname;
      };
      modules = [
        ./hosts/${darwinHostname}
        home-manager.darwinModules.home-manager
        nix-homebrew.darwinModules.nix-homebrew
        {
          users.users.${username}.home = "/Users/${username}";

          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = {
            inherit inputs self username;
            hostname = darwinHostname;
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

    homeConfigurations.${linuxHostname} = home-manager.lib.homeManagerConfiguration {
      pkgs = linuxPkgs;
      extraSpecialArgs = {
        inherit inputs self username;
        hostname = linuxHostname;
      };
      modules = [
        ./hosts/${linuxHostname}
      ];
    };
  };
}
