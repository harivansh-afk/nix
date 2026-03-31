{
  config,
  lib,
  pkgs,
  ...
}:
let
  theme = import ../lib/theme.nix { inherit config; };
in
{
  home.packages = [ pkgs.pure-prompt ];

  programs.zsh.initContent = lib.mkMerge [
    (lib.mkOrder 800 ''
      fpath+=("${pkgs.pure-prompt}/share/zsh/site-functions")
      autoload -Uz promptinit && promptinit

      export PURE_PROMPT_SYMBOL=$'\xe2\x9d\xaf'
      export PURE_PROMPT_VICMD_SYMBOL=$'\xe2\x9d\xae'
      export PURE_GIT_DIRTY=""
      export PURE_GIT_UP_ARROW="^"
      export PURE_GIT_DOWN_ARROW="v"
      export PURE_GIT_STASH_SYMBOL="="
      export PURE_CMD_MAX_EXEC_TIME=5
      export PURE_GIT_PULL=0
      export PURE_GIT_UNTRACKED_DIRTY=1
      zstyle ':prompt:pure:git:stash' show yes

      ${theme.renderPurePrompt "dark"}

      typeset -g prompt_newline=' '
      prompt pure

      prompt_pure_preprompt_render() {
        setopt localoptions noshwordsplit
        unset prompt_pure_async_render_requested

        typeset -g prompt_pure_git_branch_color=$prompt_pure_colors[git:branch]
        [[ -n ''${prompt_pure_git_last_dirty_check_timestamp+x} ]] && prompt_pure_git_branch_color=$prompt_pure_colors[git:branch:cached]

        # Branch + arrows turn yellow when dirty
        if [[ -n $prompt_pure_git_dirty ]]; then
          prompt_pure_git_branch_color=$prompt_pure_colors[git:dirty]
          prompt_pure_colors[git:arrow]=$prompt_pure_colors[git:dirty]
        else
          prompt_pure_colors[git:arrow]=$_codex_pure_default_arrow
        fi

        psvar[12]=; ((''${(M)#jobstates:#suspended:*} != 0)) && psvar[12]=''${PURE_SUSPENDED_JOBS_SYMBOL:-✦}
        psvar[13]=; [[ -n $prompt_pure_state[username] ]] && psvar[13]=1
        psvar[14]=''${prompt_pure_vcs_info[branch]}
        psvar[15]=
        psvar[16]=''${prompt_pure_vcs_info[action]}
        psvar[17]=''${prompt_pure_git_arrows}
        psvar[18]=; [[ -n $prompt_pure_git_stash ]] && psvar[18]=1
        psvar[19]=''${prompt_pure_cmd_exec_time}

        local expanded_prompt
        expanded_prompt="''${(S%%)PROMPT}"

        if [[ $1 != precmd && $prompt_pure_last_prompt != $expanded_prompt ]]; then
          prompt_pure_reset_prompt
        fi

        typeset -g prompt_pure_last_prompt=$expanded_prompt
      }

      typeset -g _codex_pure_default_arrow=$prompt_pure_colors[git:arrow]

      _codex_apply_prompt_theme() {
        local mode="$(_codex_read_theme_mode)"
        [[ "$mode" == "''${_CODEX_LAST_PROMPT_THEME:-}" ]] && return

        if [[ "$mode" == light ]]; then
          ${theme.renderPurePrompt "light"}
        else
          ${theme.renderPurePrompt "dark"}
        fi

        typeset -g _codex_pure_default_arrow=$prompt_pure_colors[git:arrow]
        typeset -g _CODEX_LAST_PROMPT_THEME="$mode"
      }
    '')
  ];
}
