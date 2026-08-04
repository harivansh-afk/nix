{
  inputs,
  lib,
  pkgs,
  self,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  userConfig = import ../../modules/users/user-config.nix {
    inherit lib pkgs;
    user = {
      name = "root";
      homeDirectory = "/root";
    };
    dotsRoot = ../../dots;
    hostname = "ix";
    isDarwin = false;
    installMutableTools = false;
    extraPackages = [
      self.packages.${system}.omp
      inputs.hermes-agent.packages.${system}.default
      pkgs.claude-code
      pkgs.codex
    ];
  };
in
{
  boot.isContainer = true;

  nixpkgs.config.allowUnfree = true;

  programs.zsh.enable = true;

  users.users.root = {
    inherit (userConfig) packages;
    shell = pkgs.zsh;
  };

  system.activationScripts.userConfig-root = {
    deps = [
      "users"
      "groups"
    ];
    text = "${userConfig.script}";
  };

  system.stateVersion = "25.11";
}
