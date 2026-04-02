{
  config,
  lib,
  pkgs,
  hostConfig,
  theme,
  ...
}:
{
  programs.zsh = {
    enable = true;
    dotDir = config.home.homeDirectory;
    enableCompletion = false;
    defaultKeymap = "viins";

    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    history = {
      size = 50000;
      save = 50000;
      ignoreDups = true;
      ignoreAllDups = true;
      ignoreSpace = true;
      extended = true;
      append = true;
      path = "${config.xdg.stateHome}/zsh_history";
    };

    shellAliases = {
      co = "codex --dangerously-bypass-approvals-and-sandbox";
      ca = "cursor-agent";
      cc = "claude";
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

    envExtra = ''
      if [[ -f "$HOME/.cargo/env" ]]; then
        . "$HOME/.cargo/env"
      fi
      export NODE_NO_WARNINGS=1
    ''
    + lib.optionalString hostConfig.isDarwin ''
      export GHOSTTY_RESOURCES_DIR="${pkgs.ghostty-bin}/Applications/Ghostty.app/Contents/Resources/ghostty"
    ''
    + ''
      export MANPAGER="nvim +Man!"
    '';

    initContent = lib.mkMerge [
      (lib.mkOrder 550 ''
        autoload -U compinit && compinit -d "${config.xdg.stateHome}/zcompdump" -u
        zmodload zsh/complist
        zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-za-z}'
      '')

      (lib.mkOrder 1000 ''
        if [[ -f ~/.config/secrets/shell.zsh ]]; then
          source ~/.config/secrets/shell.zsh
        elif [[ -f ~/.secrets ]]; then
          source ~/.secrets
        fi

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
          "/etc/profiles/per-user/${config.home.username}/bin"
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
          _codex_cursor_beam
        }
        preexec() { _codex_cursor_beam; }

        _codex_apply_prompt_theme
        _codex_apply_highlight_styles

      '')

      (lib.mkAfter ''
        bindkey '^k' forward-char
        bindkey '^j' backward-char
      '')
    ];
  };
}
