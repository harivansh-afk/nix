# vim:ft=zsh ts=2 sw=2 sts=2
#
# agnoster's Theme - https://gist.github.com/3712874
# A Powerline-inspired theme for ZSH

### Segment drawing
CURRENT_BG='NONE'

case ${SOLARIZED_THEME:-dark} in
    light)
      CURRENT_FG=${CURRENT_FG:-'white'}
      CURRENT_DEFAULT_FG=${CURRENT_DEFAULT_FG:-'white'}
      ;;
    *)
      CURRENT_FG=${CURRENT_FG:-'black'}
      CURRENT_DEFAULT_FG=${CURRENT_DEFAULT_FG:-'default'}
      ;;
esac

### Theme Configuration Initialization
: ${AGNOSTER_DIR_FG:=${CURRENT_FG}}
: ${AGNOSTER_DIR_BG:=blue}

: ${AGNOSTER_CONTEXT_FG:=${CURRENT_DEFAULT_FG}}
: ${AGNOSTER_CONTEXT_BG:=black}

: ${AGNOSTER_GIT_CLEAN_FG:=${CURRENT_FG}}
: ${AGNOSTER_GIT_CLEAN_BG:=green}
: ${AGNOSTER_GIT_DIRTY_FG:=black}
: ${AGNOSTER_GIT_DIRTY_BG:=yellow}

: ${AGNOSTER_BZR_CLEAN_FG:=${CURRENT_FG}}
: ${AGNOSTER_BZR_CLEAN_BG:=green}
: ${AGNOSTER_BZR_DIRTY_FG:=black}
: ${AGNOSTER_BZR_DIRTY_BG:=yellow}

: ${AGNOSTER_HG_NEWFILE_FG:=white}
: ${AGNOSTER_HG_NEWFILE_BG:=red}
: ${AGNOSTER_HG_CHANGED_FG:=black}
: ${AGNOSTER_HG_CHANGED_BG:=yellow}
: ${AGNOSTER_HG_CLEAN_FG:=${CURRENT_FG}}
: ${AGNOSTER_HG_CLEAN_BG:=green}

: ${AGNOSTER_VENV_FG:=black}
: ${AGNOSTER_VENV_BG:=blue}

: ${AGNOSTER_AWS_PROD_FG:=yellow}
: ${AGNOSTER_AWS_PROD_BG:=red}
: ${AGNOSTER_AWS_FG:=black}
: ${AGNOSTER_AWS_BG:=green}

: ${AGNOSTER_STATUS_RETVAL_FG:=red}
: ${AGNOSTER_STATUS_ROOT_FG:=yellow}
: ${AGNOSTER_STATUS_JOB_FG:=cyan}
: ${AGNOSTER_STATUS_FG:=${CURRENT_DEFAULT_FG}}
: ${AGNOSTER_STATUS_BG:=black}

: ${AGNOSTER_STATUS_RETVAL_NUMERIC:=false}
: ${AGNOSTER_GIT_INLINE:=false}
: ${AGNOSTER_GIT_BRANCH_STATUS:=true}

() {
  local LC_ALL="" LC_CTYPE="en_US.UTF-8"
  SEGMENT_SEPARATOR=$'\ue0b0'
}

prompt_segment() {
  local bg fg
  [[ -n $1 ]] && bg="%K{$1}" || bg="%k"
  [[ -n $2 ]] && fg="%F{$2}" || fg="%f"
  if [[ $CURRENT_BG != 'NONE' && $1 != $CURRENT_BG ]]; then
    echo -n " %{$bg%F{$CURRENT_BG}%}$SEGMENT_SEPARATOR%{$fg%} "
  else
    echo -n "%{$bg%}%{$fg%} "
  fi
  CURRENT_BG=$1
  [[ -n $3 ]] && echo -n $3
}

prompt_end() {
  if [[ -n $CURRENT_BG ]]; then
    echo -n " %{%k%F{$CURRENT_BG}%}$SEGMENT_SEPARATOR"
  else
    echo -n "%{%k%}"
  fi
  echo -n "%{%f%}"
  CURRENT_BG=''
}

git_toplevel() {
  local repo_root=$(git rev-parse --show-toplevel)
  if [[ $repo_root = '' ]]; then
    repo_root=$(git rev-parse --git-dir)
    [[ $repo_root = '.' ]] && repo_root=$PWD
  fi
  echo -n $repo_root
}

### Prompt components

prompt_context() {
  if [[ -n "$SSH_CLIENT" ]]; then
    prompt_segment "$AGNOSTER_CONTEXT_BG" "$AGNOSTER_CONTEXT_FG" "%(!.%{%F{$AGNOSTER_STATUS_ROOT_FG}%}.)%n@%m"
  fi
}

prompt_git_relative() {
  local repo_root=$(git_toplevel)
  local path_in_repo=$(pwd | sed "s/^$(echo "$repo_root" | sed 's:/:\\/:g;s/\$/\\$/g')//;s:^/::;s:/$::;")
  [[ $path_in_repo != '' ]] && prompt_segment "$AGNOSTER_DIR_BG" "$AGNOSTER_DIR_FG" "$path_in_repo"
}

prompt_git() {
  (( $+commands[git] )) || return
  [[ "$(command git config --get oh-my-zsh.hide-status 2>/dev/null)" = 1 ]] && return

  local PL_BRANCH_CHAR
  () { local LC_ALL="" LC_CTYPE="en_US.UTF-8"; PL_BRANCH_CHAR=$'\ue0a0' }

  if [[ "$(command git rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ]]; then
    local dirty ref
    dirty=$(parse_git_dirty)
    ref=$(command git symbolic-ref HEAD 2>/dev/null) || \
         ref="➦ $(command git rev-parse --short HEAD 2>/dev/null)"

    if [[ -n $dirty ]]; then
      prompt_segment "$AGNOSTER_GIT_DIRTY_BG" "$AGNOSTER_GIT_DIRTY_FG"
    else
      prompt_segment "$AGNOSTER_GIT_CLEAN_BG" "$AGNOSTER_GIT_CLEAN_FG"
    fi

    echo -n "${${ref:gs/%/%%}/refs\/heads\//$PL_BRANCH_CHAR }"
  fi
}

prompt_dir() {
  if [[ $AGNOSTER_GIT_INLINE == 'true' ]] && $(git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
    prompt_segment "$AGNOSTER_DIR_BG" "$AGNOSTER_DIR_FG" "$(git_toplevel | sed "s:^$HOME:~:")"
  else
    prompt_segment "$AGNOSTER_DIR_BG" "$AGNOSTER_DIR_FG" '%~'
  fi
}

prompt_virtualenv() {
  return
}

prompt_status() {
  local -a symbols
  [[ $AGNOSTER_STATUS_RETVAL_NUMERIC == 'true' && $RETVAL -ne 0 ]] && symbols+="%{%F{$AGNOSTER_STATUS_RETVAL_FG}%}$RETVAL"
  [[ $AGNOSTER_STATUS_RETVAL_NUMERIC != 'true' && $RETVAL -ne 0 ]] && symbols+="%{%F{$AGNOSTER_STATUS_RETVAL_FG}%}✘"
  [[ $UID -eq 0 ]] && symbols+="%{%F{$AGNOSTER_STATUS_ROOT_FG}%}⚡"
  [[ $(jobs -l | wc -l) -gt 0 ]] && symbols+="%{%F{$AGNOSTER_STATUS_JOB_FG}%}⚙"
  [[ -n "$symbols" ]] && prompt_segment "$AGNOSTER_STATUS_BG" "$AGNOSTER_STATUS_FG" "$symbols"
}

prompt_aws() {
  [[ -z "$AWS_PROFILE" || "$SHOW_AWS_PROMPT" = false ]] && return
  case "$AWS_PROFILE" in
    *-prod|*production*) prompt_segment "$AGNOSTER_AWS_PROD_BG" "$AGNOSTER_AWS_PROD_FG" "AWS: ${AWS_PROFILE:gs/%/%%}" ;;
    *) prompt_segment "$AGNOSTER_AWS_BG" "$AGNOSTER_AWS_FG" "AWS: ${AWS_PROFILE:gs/%/%%}" ;;
  esac
}

prompt_terraform() {
  local terraform_info=$(tf_prompt_info)
  [[ -z "$terraform_info" ]] && return
  prompt_segment magenta yellow "TF: $terraform_info"
}

build_prompt() {
  RETVAL=$?
  prompt_status
  prompt_virtualenv
  prompt_aws
  prompt_terraform
  prompt_context
  prompt_dir
  prompt_git
  prompt_end
}

PROMPT='%{%f%b%k%}$(build_prompt) '
