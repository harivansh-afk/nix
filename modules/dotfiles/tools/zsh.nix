{
  config,
  lib,
  pkgs,
  hostConfig,
  theme,
  inputs,
  username,
  ...
}:
let
  userSecretRegistry = (import ../../../secrets/registry.nix { inherit username inputs; }).user;
  userSecretNames = builtins.attrNames userSecretRegistry;
  loadUserSecrets = lib.concatMapStringsSep "\n" (name: ''
    if [[ -r /run/secrets/${name} ]]; then
      set -a; source /run/secrets/${name}; set +a
    fi
  '') userSecretNames;

  shellAliases = {
    ca = "cursor-agent";
    agent-claude = "cursor-agent --model=claude-opus-4-7 --force";
    agent-codex = "cursor-agent --model=gpt-5.4-xhigh-fast --force";
    cc = "claude --model 'claude-opus-4-7[1m]' --system-prompt \"$CLAUDE_SYS_PROMPT\"";
    ccf = "claude --model 'claude-opus-4-6[1m]' --settings '{\"fastMode\":true}'";
    ch = "claude-handoff";
    cl = "clear";
    gc = "git commit";
    gd = "git diff";
    gk = "git checkout";
    gp = "git push";
    gpo = "git pull origin";
    gs = "git status";
    ld = "lumen diff";
    lg = "lazygit";
    nim = "nvim .";
  }
  // lib.optionalAttrs hostConfig.isDarwin {
    tailscale = "/Applications/Tailscale.app/Contents/MacOS/Tailscale";
  };

  aliasLines = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (k: v: "alias ${k}=${lib.escapeShellArg v}") shellAliases
  );

  exportLines = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") config.sessionVars
  );

  pathLines = lib.concatStringsSep "\n" (map (p: "path=( \"${p}\" $path )") config.sessionPath);

  zshenv = ''
    typeset -U path PATH
    ${pathLines}
    export PATH
    ${exportLines}
    if [[ -f "$HOME/.cargo/env" ]]; then
      . "$HOME/.cargo/env"
    fi
    export CLAUDE_CODE_ENABLE_OPUS_4_7_FAST_MODE=1
    export NODE_NO_WARNINGS=1
    ${lib.optionalString hostConfig.isDarwin ''
      export GHOSTTY_RESOURCES_DIR="/Applications/Ghostty.app/Contents/Resources/ghostty"
    ''}
  '';

  zshrcText = ''
    # vi mode
    bindkey -v

    # history
    HISTSIZE=50000
    SAVEHIST=50000
    HISTFILE="${config.xdg.stateHome}/zsh_history"
    setopt hist_ignore_all_dups hist_ignore_space extended_history inc_append_history

    # aliases
    ${aliasLines}

    # All other init from tools, ordered by mkOrder priority
    ${config.zshInit}
  '';
in
{
  packages = with pkgs; [
    zsh
    zsh-syntax-highlighting
    zsh-autosuggestions
  ];

  files.".zshenv".text = zshenv;
  files.".zshrc".text = zshrcText;

  zshInit = lib.mkMerge [
    # 550 - compinit setup (matches original home/zsh.nix mkOrder 550)
    (lib.mkOrder 550 ''
      autoload -U compinit && compinit -d "${config.xdg.stateHome}/zcompdump" -u
      zmodload zsh/complist
      zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-za-z}'
    '')

    # 1000 - main init (matches original home/zsh.nix mkOrder 1000)
    (lib.mkOrder 1000 ''
      if [[ -f ~/.config/secrets/shell.zsh ]]; then
        source ~/.config/secrets/shell.zsh
      elif [[ -f ~/.secrets ]]; then
        source ~/.secrets
      fi

      ${loadUserSecrets}

      [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

      export BUN_INSTALL="$HOME/.bun"
      typeset -U path PATH
      path=(
        "$HOME/.amp/bin"
        "$BUN_INSTALL/bin"
        "$HOME/.antigravity/antigravity/bin"
        "$HOME/.opencode/bin"
        "$(npm prefix -g 2>/dev/null)/bin"
        "${pkgs.postgresql_17}/bin"
        "$HOME/.nix-profile/bin"
        "/run/wrappers/bin"
        "/etc/profiles/per-user/${config.username}/bin"
        "/run/current-system/sw/bin"
        "/nix/var/nix/profiles/default/bin"
        ${lib.optionalString hostConfig.isDarwin ''
          "/opt/homebrew/bin"
          "/opt/homebrew/sbin"
        ''}
        $path
      )

      _codex_read_theme_mode() {
        local mode_file="$HOME/.local/state/theme/current"
        if [[ -f "$mode_file" ]]; then
          local mode
          mode=$(tr -d '[:space:]' < "$mode_file")
          if [[ "$mode" == light || "$mode" == dark ]]; then
            printf '%s' "$mode"
            return
          fi
        fi
        printf 'dark'
      }

      _codex_apply_highlight_styles() {
        local mode="$(_codex_read_theme_mode)"
        [[ "$mode" == "''${_CODEX_LAST_HIGHLIGHT_THEME:-}" ]] && return

        typeset -gA ZSH_HIGHLIGHT_STYLES
        if [[ "$mode" == light ]]; then
          ${theme.renderZshHighlights "light"}
        else
          ${theme.renderZshHighlights "dark"}
        fi
        typeset -g _CODEX_LAST_HIGHLIGHT_THEME="$mode"
      }

      _codex_apply_bat_theme() {
        local mode="$(_codex_read_theme_mode)"
        if [[ "$mode" == light ]]; then
          export BAT_THEME='${theme.batTheme "light"}'
        else
          export BAT_THEME='${theme.batTheme "dark"}'
        fi
      }

      _codex_trust_target() {
        local target
        local common_dir
        common_dir="$(command git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" && target="$(dirname "$common_dir")" || target="$PWD"
        builtin cd -q "$target" 2>/dev/null && pwd -P || printf '%s\n' "$target"
      }

      _codex_trusted() {
        local effort="$1"
        shift
        local target
        target="$(_codex_trust_target)"
        codex --model gpt-5.5 -c "model_reasoning_effort=$effort" -c "projects={\"$target\"={trust_level=\"trusted\"}}" --dangerously-bypass-approvals-and-sandbox "$@"
      }

      co() {
        _codex_trusted low "$@"
      }

      coh() {
        _codex_trusted xhigh "$@"
      }

      unalias ga 2>/dev/null

      git() {
        command git "$@"
        local exit_code=$?
        case "$1" in
          add|stage|reset|checkout)
            if command -v critic >/dev/null 2>&1; then
              ( critic review 2>/dev/null & )
            fi
            ;;
        esac
        return $exit_code
      }

      autoload -Uz add-zle-hook-widget
      _codex_cursor() { printf '\e[%s q' "''${1:-6}"; }
      _codex_cursor_select() { [[ "$KEYMAP" == vicmd ]] && _codex_cursor 2 || _codex_cursor 6; }
      _codex_cursor_beam() { _codex_cursor 6; }
      add-zle-hook-widget zle-keymap-select _codex_cursor_select
      add-zle-hook-widget zle-line-init _codex_cursor_beam
      add-zle-hook-widget zle-line-finish _codex_cursor_beam

      precmd() {
        _codex_apply_prompt_theme
        _codex_apply_highlight_styles
        _codex_apply_bat_theme
        _codex_cursor_beam
      }
      preexec() { _codex_cursor_beam; }

      _codex_apply_prompt_theme
      _codex_apply_highlight_styles
      _codex_apply_bat_theme
    '')

    # mkAfter - bindkeys + syntax-highlighting + autosuggestions
    (lib.mkAfter ''
      bindkey '^k' forward-char
      bindkey '^j' backward-char

      source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
      source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    '')
  ];
}
