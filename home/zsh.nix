{
  config,
  lib,
  pkgs,
  ...
}:
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
    // lib.optionalAttrs pkgs.stdenv.isDarwin {
      tailscale = "/Applications/Tailscale.app/Contents/MacOS/Tailscale";
    };

    envExtra = ''
      if [[ -f "$HOME/.cargo/env" ]]; then
        . "$HOME/.cargo/env"
      fi
      export NODE_NO_WARNINGS=1
    ''
    + lib.optionalString pkgs.stdenv.isDarwin ''
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

        eval "$(zoxide init zsh)"

        [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

        export BUN_INSTALL="$HOME/.bun"
        export PNPM_HOME="${
          if pkgs.stdenv.isDarwin then "$HOME/Library/pnpm" else "${config.xdg.dataHome}/pnpm"
        }"
        bindkey -v
        typeset -U path PATH
        path=(
          "$HOME/.amp/bin"
          "$PNPM_HOME"
          "$BUN_INSTALL/bin"
          "$HOME/.antigravity/antigravity/bin"
          "$HOME/.opencode/bin"
          "${pkgs.postgresql_17}/bin"
          "$HOME/.local/bin"
          "$HOME/.nix-profile/bin"
          "/etc/profiles/per-user/${config.home.username}/bin"
          "/run/current-system/sw/bin"
          "/nix/var/nix/profiles/default/bin"
          ${lib.optionalString pkgs.stdenv.isDarwin ''
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
            ZSH_HIGHLIGHT_STYLES[arg0]='fg=#427b58'
            ZSH_HIGHLIGHT_STYLES[autodirectory]='fg=#427b58,underline'
            ZSH_HIGHLIGHT_STYLES[back-dollar-quoted-argument]='fg=#076678'
            ZSH_HIGHLIGHT_STYLES[back-double-quoted-argument]='fg=#076678'
            ZSH_HIGHLIGHT_STYLES[back-quoted-argument-delimiter]='fg=#8f3f71'
            ZSH_HIGHLIGHT_STYLES[bracket-error]='fg=#ea6962,bold'
            ZSH_HIGHLIGHT_STYLES[bracket-level-1]='fg=#076678,bold'
            ZSH_HIGHLIGHT_STYLES[bracket-level-2]='fg=#427b58,bold'
            ZSH_HIGHLIGHT_STYLES[bracket-level-3]='fg=#8f3f71,bold'
            ZSH_HIGHLIGHT_STYLES[bracket-level-4]='fg=#b57614,bold'
            ZSH_HIGHLIGHT_STYLES[bracket-level-5]='fg=#076678,bold'
            ZSH_HIGHLIGHT_STYLES[comment]='fg=#928374'
            ZSH_HIGHLIGHT_STYLES[command-substitution-delimiter]='fg=#8f3f71'
            ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument]='fg=#076678'
            ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]='fg=#b57614'
            ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#b57614'
            ZSH_HIGHLIGHT_STYLES[global-alias]='fg=#076678'
            ZSH_HIGHLIGHT_STYLES[globbing]='fg=#076678'
            ZSH_HIGHLIGHT_STYLES[history-expansion]='fg=#076678'
            ZSH_HIGHLIGHT_STYLES[path]='fg=#3c3836,underline'
            ZSH_HIGHLIGHT_STYLES[precommand]='fg=#427b58,underline'
            ZSH_HIGHLIGHT_STYLES[process-substitution-delimiter]='fg=#8f3f71'
            ZSH_HIGHLIGHT_STYLES[rc-quote]='fg=#076678'
            ZSH_HIGHLIGHT_STYLES[redirection]='fg=#b57614'
            ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=#b57614'
            ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#b57614'
            ZSH_HIGHLIGHT_STYLES[suffix-alias]='fg=#427b58,underline'
            ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#ea6962,bold'
          else
            ZSH_HIGHLIGHT_STYLES[arg0]='fg=#8ec97c'
            ZSH_HIGHLIGHT_STYLES[autodirectory]='fg=#8ec97c,underline'
            ZSH_HIGHLIGHT_STYLES[back-dollar-quoted-argument]='fg=#8ec07c'
            ZSH_HIGHLIGHT_STYLES[back-double-quoted-argument]='fg=#8ec07c'
            ZSH_HIGHLIGHT_STYLES[back-quoted-argument-delimiter]='fg=#d3869b'
            ZSH_HIGHLIGHT_STYLES[bracket-error]='fg=#ea6962,bold'
            ZSH_HIGHLIGHT_STYLES[bracket-level-1]='fg=#5b84de,bold'
            ZSH_HIGHLIGHT_STYLES[bracket-level-2]='fg=#8ec97c,bold'
            ZSH_HIGHLIGHT_STYLES[bracket-level-3]='fg=#d3869b,bold'
            ZSH_HIGHLIGHT_STYLES[bracket-level-4]='fg=#d8a657,bold'
            ZSH_HIGHLIGHT_STYLES[bracket-level-5]='fg=#8ec07c,bold'
            ZSH_HIGHLIGHT_STYLES[comment]='fg=#7c6f64'
            ZSH_HIGHLIGHT_STYLES[command-substitution-delimiter]='fg=#d3869b'
            ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument]='fg=#8ec07c'
            ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]='fg=#d8a657'
            ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#d8a657'
            ZSH_HIGHLIGHT_STYLES[global-alias]='fg=#8ec07c'
            ZSH_HIGHLIGHT_STYLES[globbing]='fg=#5b84de'
            ZSH_HIGHLIGHT_STYLES[history-expansion]='fg=#5b84de'
            ZSH_HIGHLIGHT_STYLES[path]='fg=#d4be98,underline'
            ZSH_HIGHLIGHT_STYLES[precommand]='fg=#8ec97c,underline'
            ZSH_HIGHLIGHT_STYLES[process-substitution-delimiter]='fg=#d3869b'
            ZSH_HIGHLIGHT_STYLES[rc-quote]='fg=#8ec07c'
            ZSH_HIGHLIGHT_STYLES[redirection]='fg=#d8a657'
            ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=#d8a657'
            ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#d8a657'
            ZSH_HIGHLIGHT_STYLES[suffix-alias]='fg=#8ec97c,underline'
            ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#ea6962,bold'
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

        ${lib.optionalString pkgs.stdenv.isDarwin ''
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
