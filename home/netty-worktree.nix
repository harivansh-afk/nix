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
    wt() {
      if [[ "''${1:-}" == remove ]]; then
        local current_worktree_root common_git_dir main_repo_root

        current_worktree_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
          command wt "$@"
          return
        }

        common_git_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return
        main_repo_root=$(cd "''${common_git_dir}/.." && pwd -P) || return

        command wt "$@" || return
        cd -- "$main_repo_root" || return
        return
      fi

      command wt "$@"
    }

    wtc() {
      if [[ $# -ne 1 ]]; then
        printf 'usage: wtc <worktree-name>\n' >&2
        return 1
      fi

      local worktree_path
      worktree_path=$(wt create "$1") || return
      cd -- "$worktree_path" || return
    }
  '';
}
