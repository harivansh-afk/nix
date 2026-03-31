{
  config,
  lib,
  pkgs,
  hostConfig,
  ...
}:
let
  theme = import ../lib/theme.nix { inherit config; };
in
{
  home.file.".oh-my-zsh/custom/themes/agnoster.zsh-theme".source = ../config/agnoster.zsh-theme;

  home.activation.ensureOhMyZshCache = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${config.xdg.cacheHome}/oh-my-zsh"
  '';

  home.packages = [ pkgs.oh-my-zsh ];

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
      # Ghostty shell integration expects a resource directory; the Nix app
      # bundle lives in the store instead of /Applications.
      export GHOSTTY_RESOURCES_DIR="${pkgs.ghostty-bin}/Applications/Ghostty.app/Contents/Resources/ghostty"
    ''
    + ''
      export MANPAGER="nvim +Man!"
    '';

    initContent = lib.mkMerge [
      (lib.mkOrder 550 ''
        # OpenSpec shell completions configuration
        fpath=("$HOME/.oh-my-zsh/custom/completions" $fpath)
      '')

      (lib.mkOrder 800 ''
        export ZSH="${pkgs.oh-my-zsh}/share/oh-my-zsh"
        export ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
        export ZSH_CACHE_DIR="${config.xdg.cacheHome}/oh-my-zsh"
        ZSH_THEME="agnoster"
        plugins=(git)
        ZSH_DISABLE_COMPFIX=true
        source "$ZSH/oh-my-zsh.sh"
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
          "${pkgs.postgresql_17}/bin"
          "$HOME/.nix-profile/bin"
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
          if [[ "$mode" == "''${_CODEX_LAST_HIGHLIGHT_THEME:-}" ]]; then
            return
          fi

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

        function _codex_set_cursor {
          if [[ "$1" == block ]]; then
            printf '\e[2 q'
          else
            printf '\e[6 q'
          fi
        }

        function zle-keymap-select {
          if [[ "$KEYMAP" == vicmd ]]; then
            _codex_set_cursor block
          else
            _codex_set_cursor beam
          fi
        }
        zle -N zle-keymap-select

        function zle-line-init {
          _codex_set_cursor beam
        }
        zle -N zle-line-init

        function zle-line-finish {
          _codex_set_cursor beam
        }
        zle -N zle-line-finish

        precmd() {
          _codex_apply_highlight_styles
          _codex_set_cursor beam
        }

        preexec() {
          _codex_set_cursor beam
        }

        _codex_apply_highlight_styles

        ${lib.optionalString hostConfig.isDarwin ''
          if command -v wt >/dev/null 2>&1; then
            eval "$(command wt config shell init zsh)"

            # `wt` changes directories by sourcing directives into the current shell,
            # so wrappers around it must stay shell functions instead of scripts.
            wtc() {
              wt switch --create --base @ "$@"
            }
          fi
        ''}
      '')

      (lib.mkAfter ''
        bindkey '^k' forward-car
        bindkey '^j' backward-car
      '')
    ];
  };
}
