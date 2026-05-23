{
  pkgs,
  lib,
  ...
}:
let
  nvimConfig = lib.cleanSourceWith {
    src = ../../../dots/nvim;
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

  nvimAliases = pkgs.runCommand "nvim-aliases" { } ''
    mkdir -p $out/bin
    ln -s ${pkgs.neovim}/bin/nvim $out/bin/vi
    ln -s ${pkgs.neovim}/bin/nvim $out/bin/vim
    ln -s ${pkgs.neovim}/bin/nvim $out/bin/vimdiff
  '';
in
{
  packages = [
    pkgs.neovim
    nvimAliases
    pkgs.bat
    pkgs.clang
    pkgs.clang-tools
    pkgs.elixir_1_19
    pkgs.elixir-ls
    pkgs.fd
    pkgs.fzf
    pkgs.gh
    pkgs.git
    pkgs.go_1_26
    pkgs.gopls
    pkgs.lua-language-server
    pkgs.pyright
    python
    pkgs.python3
    pkgs.ripgrep
    pkgs.stylua
    pkgs.tree-sitter
    pkgs.vscode-langservers-extracted
    pkgs.bash-language-server
    pkgs.typescript
    pkgs.typescript-language-server
    pkgs.nodejs_24
    pkgs.neovim-node-client
  ];

  sessionVars.MANPAGER = "nvim +Man!";

  files.".config/nvim" = {
    source = nvimConfig;
    recursive = true;
  };
}
