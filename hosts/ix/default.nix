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

  # Pin claude-code to the latest release: the nixpkgs pin lags behind.
  # Checksums come from the official release manifest at
  # https://downloads.claude.ai/claude-code-releases/<version>/manifest.json
  claudeCodeVersion = "2.1.222";
  claudeCodePlatform = "${pkgs.stdenv.hostPlatform.node.platform}-${pkgs.stdenv.hostPlatform.node.arch}";
  claudeCodeChecksums = {
    darwin-arm64 = "c66a6cc6fa2e8145bb1a6e77831f2caf4b83690ff04650500dfa6e2c05ca997c";
    linux-arm64 = "a04be0a8d7fe0259571ab7411d51d85658d71a4a26ce62b60c908290372e6016";
    linux-x64 = "10caae8f22b915c26bfff0e013a4d45608c4f1ae287583626569156f447730e5";
  };
  claudeCode = pkgs.claude-code.overrideAttrs {
    version = claudeCodeVersion;
    src = pkgs.fetchurl {
      url = "https://downloads.claude.ai/claude-code-releases/${claudeCodeVersion}/${claudeCodePlatform}/claude";
      sha256 = claudeCodeChecksums.${claudeCodePlatform};
    };
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
      claudeCode
    ]
    ++ (with pkgs; [
      bat
      btop
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
      mkdir -p "${packDir}" "${parserDir}" /root/.config/nvim

      if [ ! -e /root/.config/nvim/nvim-pack-lock.json ]; then
        install -m 0644 ${nvimPack.lockFile} /root/.config/nvim/nvim-pack-lock.json
      fi

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
