{
  lib,
  pkgs,
  self,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  nvimPack = import ../../lib/nvim-pack.nix { inherit lib pkgs; };
  packDir = "/root/.local/share/nvim/site/pack/core/opt";
  parserDir = "/root/.local/share/nvim/site/parser";
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
  };
in
{
  boot.isContainer = true;

  nixpkgs.config.allowUnfree = true;

  programs.zsh.enable = true;

  environment.systemPackages = [ pkgs.ghostty.terminfo ];

  environment.variables.IS_SANDBOX = "1";

  users.users.root = {
    packages = [
      self.packages.${system}.omp
      userConfig.nvimAliases
    ]
    ++ (with pkgs; [
      bat
      btop
      claude-code
      codex
      direnv
      eza
      fd
      fzf
      gh
      git
      lua-language-server
      neovim
      ripgrep
      stylua
      tree-sitter
      zoxide
    ]);
    shell = pkgs.zsh;
  };

  system.activationScripts.userConfig-root = {
    deps = [
      "users"
      "groups"
    ];
    text = "${userConfig.script}";
  };

  system.activationScripts.nvimPack = {
    deps = [ "userConfig-root" ];
    text = ''
      mkdir -p "${packDir}" "${parserDir}"

      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: src: ''
          if [ ! -e "${packDir}/${name}" ]; then
            cp -r ${src} "${packDir}/${name}"
            chmod -R u+w "${packDir}/${name}"
          fi
        '') nvimPack.plugins
      )}

      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          name: grammar: ''ln -sfn ${grammar}/parser "${parserDir}/${name}.so"''
        ) nvimPack.parsers
      )}
    '';
  };

  system.stateVersion = "25.11";
}
