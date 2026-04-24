{
  config,
  lib,
  pkgs,
  ...
}:
let
  nvimConfig = lib.cleanSourceWith {
    src = ../dots/nvim;
    filter =
      path: type:
      let
        baseName = builtins.baseNameOf path;
      in
      baseName != ".git" && baseName != "lazy-lock.json" && baseName != "nvim-pack-lock.json";
  };
  python = pkgs.writeShellScriptBin "python" ''
    exec ${pkgs.python3}/bin/python3 "$@"
  '';
in
{
  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
    defaultEditor = true;
    withNodeJs = true;
    # Explicitly opt out of the legacy Ruby / Python3 Neovim remote plugin
    # hosts. Modern plugins don't need them and skipping cuts closure size.
    withRuby = false;
    withPython3 = false;

    extraPackages = with pkgs; [
      bat
      clang
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
      stylua
      tree-sitter
      vscode-langservers-extracted
      bash-language-server
      typescript
      typescript-language-server
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
