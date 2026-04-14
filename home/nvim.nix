{
  config,
  lib,
  pkgs,
  ...
}:
let
  nvimConfig = lib.cleanSourceWith {
    src = ../config/nvim;
    filter =
      path: type:
      let
        baseName = builtins.baseNameOf path;
      in
      baseName != ".git" && baseName != "lazy-lock.json" && baseName != "nvim-pack-lock.json";
  };
  packLockSeed = ../config/nvim/nvim-pack-lock.json;
  packLockPath = "${config.xdg.stateHome}/nvim/nvim-pack-lock.json";
  python = pkgs.writeShellScriptBin "python" ''
    exec ${pkgs.python3}/bin/python3 "$@"
  '';
in
{
  # Keep rust-analyzer in the user profile so it shadows rustup's proxy in
  # /run/current-system/sw/bin when Neovim resolves LSP executables.
  home.packages = [ pkgs.rust-analyzer ];

  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
    defaultEditor = true;
    withNodeJs = true;

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

  xdg.configFile."nvim/nvim-pack-lock.json".source = config.lib.file.mkOutOfStoreSymlink packLockPath;

  home.activation.seedNvimPackLock = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    state_dir="${config.xdg.stateHome}/nvim"
    lockfile="${packLockPath}"

    if [ ! -e "$lockfile" ] || ! cmp -s ${packLockSeed} "$lockfile"; then
      mkdir -p "$state_dir"
      cp ${packLockSeed} "$lockfile"
      chmod u+w "$lockfile"
    fi
  '';
}
