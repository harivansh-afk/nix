{
  config,
  lib,
  pkgs,
  ...
}: {
  home.file.".oh-my-zsh/custom/themes/agnoster.zsh-theme".source =
    ../config/agnoster.zsh-theme;

  home.activation.ensureOhMyZshCache = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p "${config.xdg.cacheHome}/oh-my-zsh"
  '';

  home.packages = [pkgs.oh-my-zsh];

  programs.zsh = {
    enable = true;
    dotDir = config.home.homeDirectory;
    enableCompletion = false;
    defaultKeymap = "viins";

    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      c = "codex --dangerously-bypass-approvals-and-sandbox";
      ca = "cursor-agent";
      cc = "claude --dangerously-skip-permissions";
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
      sshnet = "ssh -i ~/.ssh/atlas-ssh.txt rathiharivansh@152.53.195.59";
      tailscale = "/Applications/Tailscale.app/Contents/MacOS/Tailscale";
    };

    envExtra = ''
      . "$HOME/.cargo/env"

      # Ghostty shell integration expects a resource directory; the Nix app
      # bundle lives in the store instead of /Applications.
      export GHOSTTY_RESOURCES_DIR="${pkgs.ghostty-bin}/Applications/Ghostty.app/Contents/Resources/ghostty"
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
        export PNPM_HOME="$HOME/Library/pnpm"
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
          "/opt/homebrew/bin"
          "/opt/homebrew/sbin"
          $path
        )

        unalias ga 2>/dev/null
        ga() {
          if [[ $# -eq 0 ]]; then
            git add .
          else
            git add "$@"
          fi
        }

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
          _codex_set_cursor beam
        }

        preexec() {
          _codex_set_cursor beam
        }

        iosrun() {
          local project=$(find . -maxdepth 1 -name "*.xcodeproj" | head -1)
          local scheme=$(basename "$project" .xcodeproj)
          local derived=".derived-data"
          local sim_name="''${1:-iPhone 16e}"

          if [[ -z "$project" ]]; then
            echo "No .xcodeproj found in current directory"
            return 1
          fi

          echo "Building $scheme..."
          if ! xcodebuild -project "$project" -scheme "$scheme" \
            -destination "platform=iOS Simulator,name=$sim_name" \
            -derivedDataPath "$derived" build -quiet; then
            echo "Build failed"
            return 1
          fi

          echo "Build succeeded. Launching simulator..."

          xcrun simctl boot "$sim_name" 2>/dev/null
          open -a Simulator

          local app_path="$derived/Build/Products/Debug-iphonesimulator/$scheme.app"
          local bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app_path/Info.plist")

          echo "Installing $scheme..."
          while ! xcrun simctl install "$sim_name" "$app_path" 2>/dev/null; do
            sleep 0.5
          done

          echo "Launching $bundle_id..."
          while ! xcrun simctl launch "$sim_name" "$bundle_id" 2>&1 | grep -q "$bundle_id"; do
            sleep 0.5
          done

          echo "Launched $bundle_id - streaming logs (Ctrl+C to stop)"
          echo "----------------------------------------"

          xcrun simctl spawn "$sim_name" log stream \
            --predicate "(subsystem CONTAINS '$bundle_id' OR process == '$scheme') AND NOT subsystem BEGINSWITH 'com.apple'" \
            --style compact \
            --color always 2>/dev/null | while read -r line; do
            if [[ "$line" == *"error"* ]] || [[ "$line" == *"Error"* ]]; then
              echo "\033[31m$line\033[0m"
            elif [[ "$line" == *"warning"* ]] || [[ "$line" == *"Warning"* ]]; then
              echo "\033[33m$line\033[0m"
            else
              echo "$line"
            fi
          done
        }

        mdview() {
          markserv "$1"
        }

        if command -v wt >/dev/null 2>&1; then
          eval "$(command wt config shell init zsh)"
        fi

        wtc() { wt switch --create --base @ "$@"; }

        unalias gpr 2>/dev/null
        gpr() {
          while true; do
            local pr=$(gh pr list --limit 50 \
              --json number,title,author,headRefName \
              --template '{{range .}}#{{.number}} {{.title}} ({{.author.login}}) [{{.headRefName}}]{{"\n"}}{{end}}' \
              | fzf --preview 'gh pr view {1} --comments' \
                    --preview-window=right:60%:wrap \
                    --header 'enter: view | ctrl-m: merge | ctrl-x: close | ctrl-o: checkout | ctrl-b: browser' \
                    --bind 'ctrl-o:execute(gh pr checkout {1})' \
                    --bind 'ctrl-b:execute(gh pr view {1} --web)' \
                    --expect=ctrl-m,ctrl-x,enter)

            [[ -z "$pr" ]] && return

            local key=$(echo "$pr" | head -1)
            local selection=$(echo "$pr" | tail -1)
            local num=$(echo "$selection" | grep -o '#[0-9]*' | tr -d '#')

            [[ -z "$num" ]] && return

            case "$key" in
              ctrl-m)
                echo "Merge PR #$num? (y/n)"
                read -q && gh pr merge "$num" --merge
                echo
                ;;
              ctrl-x)
                echo "Close PR #$num? (y/n)"
                read -q && gh pr close "$num"
                echo
                ;;
              enter|"")
                gh pr view "$num"
                ;;
            esac
          done
        }

        ghpr() {
          local base=$(git rev-parse --abbrev-ref HEAD)
          local upstream="''${1:-main}"
          local remote_ref="origin/$upstream"
          local unpushed=$(git log "$remote_ref"..HEAD --oneline 2>/dev/null)

          if [[ -z "$unpushed" ]]; then
            if git diff --cached --quiet; then
              echo "No unpushed commits and no staged changes"
              return 1
            fi
            echo "No unpushed commits, but staged changes found. Opening commit dialog..."
            git commit || return 1
          fi

          local msg=$(git log "$remote_ref"..HEAD --format='%s' --reverse | head -1)
          local branch=$(echo "$msg" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')

          git checkout -b "$branch"
          git checkout "$base"
          git reset --hard "$remote_ref"
          git checkout "$branch"

          git push -u origin "$branch"
          gh pr create --base "$upstream" --fill --web 2>/dev/null || gh pr create --base "$upstream" --fill
          gh pr view "$branch" --json url -q '.url'
        }
      '')

      (lib.mkAfter ''
        bindkey '^k' forward-car
        bindkey '^j' backward-car
      '')
    ];
  };
}
