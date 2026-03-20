{
  config,
  lib,
  pkgs,
  ...
}: let
  nvimConfig = lib.cleanSourceWith {
    src = ../config/nvim;
    filter = path: type: builtins.baseNameOf path != ".git";
  };
  python = pkgs.writeShellScriptBin "python" ''
    exec ${pkgs.python3}/bin/python3 "$@"
  '';
in {
  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
    defaultEditor = true;
    withNodeJs = true;

    extraPackages = with pkgs; [
      bat
      clang-tools
      fd
      fzf
      gh
      git
      go_1_26
      gopls
      lua-language-server
      pyright
      python
      python3
      ripgrep
      rust-analyzer
      rustup
      stylua
      vscode-langservers-extracted
      nodePackages.bash-language-server
      nodePackages.typescript
      nodePackages.typescript-language-server
    ];
  };

  home.sessionVariables = lib.mkIf config.programs.neovim.enable {
    MANPAGER = "nvim +Man!";
  };

  xdg.configFile."nvim" = {
    source = nvimConfig;
    recursive = true;
  };
}
