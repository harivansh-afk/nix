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

typeset -g prompt_newline=' '
prompt pure

# A dirty tree drops the marker and colours the branch, arrows and prompt symbol instead.
prompt_pure_precustom() {
  prompt_pure_set_colors
  [[ -n $prompt_pure_git_dirty ]] || return
  psvar[15]=
  prompt_pure_git_branch_color=$prompt_pure_colors[git:dirty]
  prompt_pure_colors[git:arrow]=$prompt_pure_colors[git:dirty]
  prompt_pure_colors[prompt:success]=$prompt_pure_colors[git:dirty]
}
