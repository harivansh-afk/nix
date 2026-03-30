{
  config,
  lib,
  pkgs,
  ...
}: let
  customScripts = import ../scripts {inherit config lib pkgs;};
in {
  home.packages = builtins.attrValues customScripts.nettyPackages;

  programs.zsh.initContent = lib.mkAfter ''
    wtc() {
      if [[ $# -ne 1 ]]; then
        printf 'usage: wtc <worktree-name>\n' >&2
        return 1
      fi

      local worktree_path
      worktree_path=$(command wt-create "$1") || return
      cd -- "$worktree_path" || return
    }
  '';
}
