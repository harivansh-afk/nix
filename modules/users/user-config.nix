# Per-user configuration without home-manager, in the style of
# forge.barrettruth.com/barrettruth/nix: plain dotfiles under dots/ are
# symlinked into the home directory by a script that runs as the user during
# system activation. Configs that need nix store paths (zsh plugins, git
# credential helpers, theme renders) are small store-generated shims that
# defer to the live dots/ file wherever possible.
#
# Arguments:
#   user       - { name, homeDirectory }
#   dotsRoot   - string path to the dots/ directory the symlinks point at.
#                For the repo owner this is the live checkout
#                (~/Documents/Git/nix/dots) so config edits apply without a
#                rebuild; for other users it is the nix-store copy of dots/.
#   hostname   - for btop's custom_cpu_name
#   isDarwin   - platform switch for the darwin-only blocks
#
# Returns:
#   { script, packages } - script is a writeShellScript to run as the user;
#   packages is the user's package set (the old home-manager programs.* and
#   home.packages payload).
{
  lib,
  pkgs,
  user,
  dotsRoot,
  hostname,
  isDarwin,
  extraPackages ? [ ],
}:
let
  inherit (user) name homeDirectory;
  configHome = "${homeDirectory}/.config";
  binHome = "${homeDirectory}/.local/bin";
  dataHome = "${homeDirectory}/.local/share";
  stateHome = "${homeDirectory}/.local/state";
  cacheHome = "${homeDirectory}/.cache";

  theme = import ../../lib/theme.nix { inherit homeDirectory; };
  customScripts = import ../../scripts { inherit homeDirectory lib pkgs; };

  coreutilsBin = "${pkgs.coreutils}/bin";

  # --- session environment (the old home/xdg.nix + sessionVariables) ---
  sessionVars = pkgs.writeText "session-vars.zsh" ''
    export XDG_BIN_HOME="${binHome}"
    export XDG_CONFIG_HOME="${configHome}"
    export XDG_DATA_HOME="${dataHome}"
    export XDG_STATE_HOME="${stateHome}"
    export XDG_CACHE_HOME="${cacheHome}"

    export LESSHISTFILE="-"
    export WGETRC="${configHome}/wgetrc"

    export CARGO_HOME="${dataHome}/cargo"
    export RUSTUP_HOME="${dataHome}/rustup"

    export GOPATH="${dataHome}/go"
    export GOMODCACHE="${cacheHome}/go/mod"

    export NPM_CONFIG_USERCONFIG="${configHome}/npm/npmrc"
    export NODE_REPL_HISTORY="${stateHome}/node_repl_history"
    export PNPM_HOME="${dataHome}/pnpm"
    export PNPM_NO_UPDATE_NOTIFIER="true"

    export PYTHONSTARTUP="${configHome}/python/pythonrc"
    export PYTHON_HISTORY="${stateHome}/python_history"
    export PYTHONPYCACHEPREFIX="${cacheHome}/python"
    export PYTHONUSERBASE="${dataHome}/python"

    export DOCKER_CONFIG="${configHome}/docker"

    export AWS_SHARED_CREDENTIALS_FILE="${configHome}/aws/credentials"
    export AWS_CONFIG_FILE="${configHome}/aws/config"

    export PSQL_HISTORY="${stateHome}/psql_history"
    export SQLITE_HISTORY="${stateHome}/sqlite_history"

    export FZF_DEFAULT_OPTS_FILE="${theme.paths.fzfCurrentFile}"

    export PATH="${binHome}:${dataHome}/cargo/bin:${dataHome}/go/bin:${dataHome}/npm/bin:${dataHome}/pnpm:$PATH"
  '';

  environmentD = pkgs.writeText "user-environment.conf" ''
    XDG_BIN_HOME=${binHome}
    XDG_CACHE_HOME=${cacheHome}
    XDG_CONFIG_HOME=${configHome}
    XDG_DATA_HOME=${dataHome}
    XDG_STATE_HOME=${stateHome}
  '';

  # --- zsh shims: store paths first, then the live dots file ---
  userSecretRegistry = (import ../../secrets/registry.nix { username = name; }).user;
  shellSecretRegistry = lib.filterAttrs (_: cfg: cfg.exposeToShell or true) userSecretRegistry;
  loadUserSecrets = lib.concatMapStringsSep "\n" (secretName: ''
    if [[ -r /run/secrets/${secretName} ]]; then
      set -a; source /run/secrets/${secretName}; set +a
    fi
  '') (builtins.attrNames shellSecretRegistry);

  zshenvShim = pkgs.writeText "zshenv-shim" ''
    source ${sessionVars}
    source "${dotsRoot}/zsh/zshenv"
  '';

  zshrcShim = pkgs.writeText "zshrc-shim" ''
    source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
    fpath+=("${pkgs.pure-prompt}/share/zsh/site-functions")

    ${loadUserSecrets}

    export DOTS_ZSH_DIR="${dotsRoot}/zsh"
    source "${dotsRoot}/zsh/zshrc"

    # syntax highlighting wants to be sourced last
    source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
  '';

  mkZshTheme =
    mode:
    pkgs.writeText "zsh-theme-${mode}.zsh" ''
      ${theme.renderPurePrompt mode}
      typeset -gA ZSH_HIGHLIGHT_STYLES
      ${theme.renderZshHighlights mode}
    '';
  zshThemes = {
    dark = mkZshTheme "dark";
    light = mkZshTheme "light";
  };

  nvimAliases = pkgs.runCommand "nvim-command-aliases" { } ''
    mkdir -p "$out/bin"
    ln -s ${pkgs.neovim}/bin/nvim "$out/bin/vi"
    ln -s ${pkgs.neovim}/bin/nvim "$out/bin/vim"
    ln -s ${pkgs.neovim}/bin/nvim "$out/bin/view"
    ln -s ${pkgs.neovim}/bin/nvim "$out/bin/vimdiff"
  '';

  # --- git: credential helpers and delta themes need nix rendering ---
  forgejoCredentialHelper = pkgs.writeShellScript "git-credential-forgejo" ''
    if [ "$1" = "get" ] && [ -r /run/secrets/forgejo-token.env ]; then
      echo "username=harivansh-afk"
      echo "password=$(cat /run/secrets/forgejo-token.env)"
    fi
  '';

  ixForgejoCredentialHelper = pkgs.writeShellScript "git-credential-ix-forgejo" ''
    if [ "$1" = "get" ] && [ -r /run/secrets/forgejo-ix.env ]; then
      set -a
      . /run/secrets/forgejo-ix.env
      echo "username=harivansh-afk"
      echo "password=$FORGEJO_IX_TOKEN"
    fi
  '';

  gitCredentialsInc = pkgs.writeText "git-credentials.inc" ''
    [credential "https://git.harivan.sh"]
    	helper = !${forgejoCredentialHelper}
    	username = harivansh-afk

    [credential "https://git.ix.dev"]
    	helper = !${ixForgejoCredentialHelper}
    	username = harivansh-afk
  '';

  renderGitSection =
    sectionName: attrs:
    let
      renderValue = v: if builtins.isBool v then (if v then "true" else "false") else toString v;
      lines = lib.mapAttrsToList (k: v: "	${k} = ${renderValue v}") attrs;
    in
    "[${sectionName}]\n" + lib.concatStringsSep "\n" lines;

  gitDeltaThemesInc = pkgs.writeText "git-delta-themes.inc" ''
    ${renderGitSection ''delta "cozybox-dark"'' (theme.deltaTheme "dark")}

    ${renderGitSection ''delta "cozybox-light"'' (theme.deltaTheme "light")}
  '';

  # --- claude settings (hook paths interpolate the home directory) ---
  jsonFormat = pkgs.formats.json { };
  hookCommand = hook: "${homeDirectory}/.claude/hooks/${hook}";
  claudeSettings = jsonFormat.generate "claude-settings.json" {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
    model = "claude-opus-4-8";
    # Stay on the classic renderer; the v2.1.110+ fullscreen TUI breaks
    # native scrollback / Cmd+f / tmux copy-mode. Override with /tui
    # fullscreen if you want to opt in for a session.
    tui = "default";
    permissions.defaultMode = "bypassPermissions";
    includeCoAuthoredBy = false;
    autoCompactEnabled = true;
    showThinkingSummaries = true;
    statusLine = {
      type = "command";
      command = "${homeDirectory}/.claude/statusline.sh";
    };
    voiceEnabled = true;
    hooks = {
      SessionStart = [
        {
          hooks = [
            {
              type = "command";
              command = hookCommand "session-start.sh";
            }
          ];
        }
        {
          hooks = [
            {
              type = "command";
              command = hookCommand "session-id.sh";
              timeout = 5;
            }
          ];
        }
      ];
      PreToolUse = [
        {
          matcher = "Bash";
          hooks = [
            {
              type = "command";
              command = hookCommand "enforce-modern-tools.sh";
            }
          ];
        }
      ];
    };
  };

  # --- themed app configs rendered from the palette ---
  btopConf = pkgs.writeText "btop.conf" ''
    color_theme = "ayu"
    custom_cpu_name = "${hostname}"
    rounded_corners = False
    theme_background = False
    vim_keys = True
  '';

  fzfThemes = {
    dark = pkgs.writeText "fzf-cozybox-dark" (theme.renderFzf "dark");
    light = pkgs.writeText "fzf-cozybox-light" (theme.renderFzf "light");
  };

  ghosttyThemes = {
    dark = pkgs.writeText "ghostty-cozybox-dark" (theme.renderGhostty "dark");
    light = pkgs.writeText "ghostty-cozybox-light" (theme.renderGhostty "light");
  };

  lazygitBase = builtins.readFile ../../dots/lazygit/config.yml;
  lazygitConfigs = {
    dark = pkgs.writeText "lazygit-config-dark.yml" (lazygitBase + theme.renderLazygit "dark");
    light = pkgs.writeText "lazygit-config-light.yml" (lazygitBase + theme.renderLazygit "light");
  };

  # --- codex seed (xattr-tracked writable copy; codex rewrites its config) ---
  codexConfigSource = "${dotsRoot}/codex/config.toml";
  xattrName = "user.hari.codex-seed-source";
  readXattr =
    if isDarwin then
      ''/usr/bin/xattr -p "${xattrName}" "$target" 2>/dev/null''
    else
      ''${pkgs.attr}/bin/getfattr --only-values -n "${xattrName}" "$target" 2>/dev/null'';
  writeXattr =
    if isDarwin then
      ''/usr/bin/xattr -w "${xattrName}" "$source" "$target"''
    else
      ''${pkgs.attr}/bin/setfattr -n "${xattrName}" -v "$source" "$target"'';

  # --- tea login fragment ---
  teaLoginYaml = pkgs.writeShellScript "tea-login-yaml" ''
    set -eu

    name="$1"
    url="$2"
    sshHost="$3"
    token="$4"
    default="$5"

    cat <<YAML
        - name: $name
          url: $url
          token: $token
          default: $default
          ssh_host: $sshHost
          ssh_key: ""
          insecure: false
          ssh_certificate_principal: ""
          ssh_agent: false
          ssh_key_agent_pub: ""
          version_check: false
          user: harivansh-afk
    YAML
  '';

  # --- helium managed extensions (darwin) ---
  heliumExtensions = [
    "ddkjiahejlhfcafbddmgiahcphecmpfh" # uBlock Origin Lite
    "fcoeoabgfenejglbffodgkkbkcdhcgfn" # Claude for Chrome
    "nngceckbapebfimnlniiiahkandclblb" # Bitwarden
  ];
  heliumExtJson = pkgs.writeText "helium-ext.json" (
    builtins.toJSON { external_update_url = "https://clients2.google.com/service/update2/crx"; }
  );

  pythonWrapper = pkgs.writeShellScriptBin "python" ''
    exec ${pkgs.python3}/bin/python3 "$@"
  '';

  # The old programs.neovim extraPackages: LSPs and tools nvim expects on PATH.
  nvimPackages = with pkgs; [
    bat
    clang
    clang-tools
    elixir_1_19
    elixir-ls
    fd
    fzf
    gh
    git
    go_1_26
    gopls
    lua-language-server
    pyright
    pythonWrapper
    python3
    ripgrep
    stylua
    tree-sitter
    vscode-langservers-extracted
    bash-language-server
    typescript
    typescript-language-server
  ];

  packages =
    (with pkgs; [
      bat
      btop
      direnv
      eza
      fzf
      git
      git-lfs
      gh
      k9s
      neovim
      nvimAliases
      tea
      tmux
    ])
    ++ nvimPackages
    ++ extraPackages
    ++ builtins.attrValues customScripts.commonPackages
    ++ lib.optionals isDarwin (builtins.attrValues customScripts.darwinPackages ++ [ pkgs.aerospace ]);

  script = pkgs.writeShellScript "user-config-${name}" ''
    set -eu
    PATH=${coreutilsBin}:$PATH
    HOME=${homeDirectory}
    export HOME

    mkSymlink() {
      target="$1"
      link="$2"
      if [ -d "$link" ] && [ ! -L "$link" ]; then
        rm -rf "$link"
      fi
      ln -sfnT "$target" "$link"
    }

    # --- directories ---
    mkdir -p \
      "${configHome}/zsh/themes" \
      "${configHome}/environment.d" \
      "${configHome}/git" \
      "${configHome}/fzf/themes" \
      "${configHome}/ghostty/themes" \
      "${configHome}/tmux/theme" \
      "${configHome}/tmux/plugins" \
      "${configHome}/lazygit" \
      "${configHome}/direnv/lib" \
      "${configHome}/k9s" \
      "${configHome}/gh" \
      "${configHome}/npm" \
      "${configHome}/python" \
      "${configHome}/btop" \
      "${configHome}/devin" \
      "${configHome}/gcloud/configurations" \
      "${configHome}/tea" \
      "${homeDirectory}/.claude/hooks" \
      "${homeDirectory}/.codex" \
      "${homeDirectory}/.local/bin" \
      "${homeDirectory}/.ssh/sockets" \
      "${stateHome}" \
      "${theme.paths.stateDir}" \
      "${theme.wallpapers.dir}"

    # --- zsh ---
    mkSymlink "${zshrcShim}" "${homeDirectory}/.zshrc"
    mkSymlink "${zshenvShim}" "${homeDirectory}/.zshenv"
    mkSymlink "${zshThemes.dark}" "${configHome}/zsh/themes/dark.zsh"
    mkSymlink "${zshThemes.light}" "${configHome}/zsh/themes/light.zsh"
    mkSymlink "${environmentD}" "${configHome}/environment.d/10-user-config.conf"

    # --- git ---
    mkSymlink "${dotsRoot}/git/config" "${configHome}/git/config"
    mkSymlink "${dotsRoot}/git/ignore" "${configHome}/git/ignore"
    mkSymlink "${gitCredentialsInc}" "${configHome}/git/credentials.inc"
    mkSymlink "${gitDeltaThemesInc}" "${configHome}/git/delta-themes.inc"

    # --- ssh ---
    mkSymlink "${dotsRoot}/ssh/config" "${homeDirectory}/.ssh/config"

    # --- tmux ---
    mkSymlink "${dotsRoot}/tmux/tmux.conf" "${configHome}/tmux/tmux.conf"
    mkSymlink "${dotsRoot}/tmux/session-list.sh" "${configHome}/tmux/session-list.sh"
    mkSymlink "${dotsRoot}/tmux/tmux-clip-relay" "${homeDirectory}/.local/bin/tmux-clip-relay"
    mkSymlink "${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect" "${configHome}/tmux/plugins/resurrect"
    mkSymlink "${pkgs.tmuxPlugins.continuum}/share/tmux-plugins/continuum" "${configHome}/tmux/plugins/continuum"

    # --- nvim: live directory symlink; salvage lock files from the old
    # home-manager symlink forest before replacing it ---
    if [ -d "${configHome}/nvim" ] && [ ! -L "${configHome}/nvim" ]; then
      for lock in lazy-lock.json nvim-pack-lock.json; do
        if [ -f "${configHome}/nvim/$lock" ] && [ ! -L "${configHome}/nvim/$lock" ] \
          && [ -w "${dotsRoot}/nvim" ] && [ ! -e "${dotsRoot}/nvim/$lock" ]; then
          cp "${configHome}/nvim/$lock" "${dotsRoot}/nvim/$lock"
        fi
      done
    fi
    mkSymlink "${dotsRoot}/nvim" "${configHome}/nvim"

    # --- assorted app configs ---
    mkSymlink "${btopConf}" "${configHome}/btop/btop.conf"
    mkSymlink "${dotsRoot}/k9s/views.yaml" "${configHome}/k9s/views.yaml"
    mkSymlink "${dotsRoot}/direnv/direnv.toml" "${configHome}/direnv/direnv.toml"
    mkSymlink "${pkgs.nix-direnv}/share/nix-direnv/direnvrc" "${configHome}/direnv/lib/nix-direnv.sh"
    mkSymlink "${dotsRoot}/wgetrc" "${configHome}/wgetrc"
    mkSymlink "${dotsRoot}/npm/npmrc" "${configHome}/npm/npmrc"
    mkSymlink "${dotsRoot}/python/pythonrc" "${configHome}/python/pythonrc"
    mkSymlink "${dotsRoot}/ghostty/config" "${configHome}/ghostty/config"
    mkSymlink "${ghosttyThemes.dark}" "${configHome}/ghostty/themes/cozybox-dark"
    mkSymlink "${ghosttyThemes.light}" "${configHome}/ghostty/themes/cozybox-light"
    mkSymlink "${fzfThemes.dark}" "${configHome}/fzf/themes/cozybox-dark"
    mkSymlink "${fzfThemes.light}" "${configHome}/fzf/themes/cozybox-light"
    mkSymlink "${lazygitConfigs.dark}" "${configHome}/lazygit/config-dark.yml"
    mkSymlink "${lazygitConfigs.light}" "${configHome}/lazygit/config-light.yml"

    # gh rewrites its config at runtime; keep a managed copy instead of a
    # read-only store symlink
    rm -f "${configHome}/gh/config.yml"
    cp -f "${dotsRoot}/gh/config.yml" "${configHome}/gh/config.yml"
    chmod u+w "${configHome}/gh/config.yml"

    # --- claude ---
    mkSymlink "${dotsRoot}/claude/CLAUDE.md" "${homeDirectory}/.claude/CLAUDE.md"
    mkSymlink "${dotsRoot}/claude/commands" "${homeDirectory}/.claude/commands"
    mkSymlink "${claudeSettings}" "${homeDirectory}/.claude/settings.json"
    mkSymlink "${dotsRoot}/claude/statusline.sh" "${homeDirectory}/.claude/statusline.sh"
    mkSymlink "${dotsRoot}/claude/hooks/session-start.sh" "${homeDirectory}/.claude/hooks/session-start.sh"
    mkSymlink "${dotsRoot}/claude/hooks/session-id.sh" "${homeDirectory}/.claude/hooks/session-id.sh"
    mkSymlink "${dotsRoot}/claude/hooks/enforce-modern-tools.sh" "${homeDirectory}/.claude/hooks/enforce-modern-tools.sh"

    # --- codex: AGENTS.md symlink, config.toml seeded as a writable copy.
    # Codex rewrites ~/.codex/config.toml at runtime (hook trust, per-project
    # trust_level, model NUX counters), so it cannot be a read-only nix-store
    # symlink. Only reseed when the managed source changes (tracked via an
    # extended attribute) so runtime mutations survive every switch. ---
    mkSymlink "${dotsRoot}/codex/AGENTS.md" "${homeDirectory}/.codex/AGENTS.md"

    target="${homeDirectory}/.codex/config.toml"
    source="${codexConfigSource}"
    current=""

    if [ -e "$target" ] && [ ! -L "$target" ]; then
      if xattr_value="$(${readXattr})"; then
        current="$xattr_value"
      fi
    fi

    if [ ! -e "$target" ] || [ -L "$target" ] || [ "$current" != "$source" ]; then
      tmp="$target.seed-tmp"
      rm -f "$target" "$tmp"
      cp "$source" "$tmp"
      chmod u+w "$tmp"
      mv "$tmp" "$target"
      ${writeXattr}
    fi

    # --- devin config: managed copy with backup of local divergence ---
    if [ -f "${configHome}/devin/config.json" ] \
      && ! ${pkgs.diffutils}/bin/cmp -s "${dotsRoot}/devin/config.json" "${configHome}/devin/config.json"; then
      timestamp="$(date +%Y%m%d%H%M%S)"
      cp "${configHome}/devin/config.json" "${configHome}/devin/config.json.bak.$timestamp"
    fi
    install -m 600 "${dotsRoot}/devin/config.json" "${configHome}/devin/config.json"

    # --- gcloud ---
    install -Dm644 /dev/null "${configHome}/gcloud/active_config"
    printf 'default' > "${configHome}/gcloud/active_config"
    install -Dm644 /dev/null "${configHome}/gcloud/configurations/config_default"
    printf '[core]\naccount=rathiharivansh@gmail.com\nproject=hari-gc\n' \
      > "${configHome}/gcloud/configurations/config_default"

    # --- tea logins from sops secrets (skipped when unreadable) ---
    harivanTokenFile=/run/secrets/forgejo-token.env
    ixTokenEnvFile=/run/secrets/forgejo-ix.env

    harivanToken=
    if [ -r "$harivanTokenFile" ]; then
      harivanToken=$(cat "$harivanTokenFile")
    fi

    ixToken=
    if [ -r "$ixTokenEnvFile" ]; then
      ixToken=$(
        set -a
        . "$ixTokenEnvFile"
        printf '%s' "$FORGEJO_IX_TOKEN"
      )
    fi

    if [ -n "$harivanToken" ] || [ -n "$ixToken" ]; then
      install -d -m 0700 "${configHome}/tea"
      umask 077
      tmp="${configHome}/tea/config.yml.tmp"

      {
        printf '%s\n' "logins:"
        if [ -n "$harivanToken" ]; then
          ${teaLoginYaml} harivan https://git.harivan.sh git.harivan.sh "$harivanToken" true
        fi
        if [ -n "$ixToken" ]; then
          if [ -n "$harivanToken" ]; then
            ixDefault=false
          else
            ixDefault=true
          fi
          ${teaLoginYaml} ix-harivansh https://git.ix.dev git.ix.dev "$ixToken" "$ixDefault"
        fi
        cat <<'YAML'
    preferences:
        editor: false
        flag_defaults:
            remote: ""
    YAML
      } > "$tmp"

      mv "$tmp" "${configHome}/tea/config.yml"
      umask 022
    fi

    # --- theme state init (the old home/scripts.nix activation) ---
    ${customScripts.themeAssetsText}

    mkdir -p "${theme.paths.stateDir}" \
             "${theme.paths.fzfDir}" \
             "${theme.paths.ghosttyDir}" \
             "${theme.paths.tmuxDir}" \
             "${theme.paths.lazygitDir}" \
             "${theme.paths.gitDir}" \
             "${theme.wallpapers.dir}"

    if [ -f "${theme.paths.stateFile}" ]; then
      mode=$(tr -d '[:space:]' < "${theme.paths.stateFile}")
    else
      mode="${theme.defaultMode}"
    fi

    mode="$(theme_normalize_mode "$mode")"
    printf '%s\n' "$mode" > "${theme.paths.stateFile}"
    theme_load_mode_assets "$mode"

    ln -sfn "$THEME_FZF_TARGET" "${theme.paths.fzfCurrentFile}"
    ln -sfn "$THEME_GHOSTTY_TARGET" "${theme.paths.ghosttyCurrentFile}"
    ln -sfn "$THEME_TMUX_TARGET" "${theme.paths.tmuxCurrentFile}"
    ln -sfn "$THEME_LAZYGIT_TARGET" "${theme.paths.lazygitCurrentFile}"
    ln -sfn "$THEME_GIT_THEME_TARGET" "${theme.paths.gitThemeCurrentFile}"

    if [ ! -f "${theme.wallpapers.dark}" ]; then
      cp "${theme.wallpapers.staticDark}" "${theme.wallpapers.dark}"
    fi
    if [ ! -f "${theme.wallpapers.light}" ]; then
      cp "${theme.wallpapers.staticLight}" "${theme.wallpapers.light}"
    fi

    ln -sfn "$THEME_WALLPAPER" "${theme.wallpapers.current}"

    ${lib.optionalString isDarwin ''
      # --- darwin: Application Support twins and GUI app configs ---
      ghostty_appsupport="${homeDirectory}/Library/Application Support/com.mitchellh.ghostty"
      mkdir -p "$ghostty_appsupport"
      mkSymlink "${dotsRoot}/ghostty/config" "$ghostty_appsupport/config"

      lg_darwin="${homeDirectory}/Library/Application Support/lazygit"
      mkdir -p "$lg_darwin"
      mkSymlink "${lazygitConfigs.dark}" "$lg_darwin/config-dark.yml"
      mkSymlink "${lazygitConfigs.light}" "$lg_darwin/config-light.yml"
      ln -sfn "$THEME_DARWIN_LAZYGIT_TARGET" "$lg_darwin/config.yml"

      # karabiner wants a writable directory; point it at the live checkout
      mkSymlink "${dotsRoot}/karabiner" "${configHome}/karabiner"

      # aerospace reads ~/.config/aerospace/aerospace.toml
      mkdir -p "${configHome}/aerospace"
      mkSymlink "${dotsRoot}/aerospace/aerospace.toml" "${configHome}/aerospace/aerospace.toml"

      # helium managed extensions
      helium_ext="${homeDirectory}/Library/Application Support/net.imput.helium/External Extensions"
      mkdir -p "$helium_ext"
      ${lib.concatMapStringsSep "\n" (id: ''
        mkSymlink "${heliumExtJson}" "$helium_ext/${id}.json"
      '') heliumExtensions}
    ''}

    # --- secret permissions ---
    if [ -d "${homeDirectory}/.ssh" ]; then
      chmod 700 "${homeDirectory}/.ssh"
      for f in "${homeDirectory}/.ssh/"*; do
        [ -f "$f" ] || continue
        [ -L "$f" ] && continue
        case "$f" in
          *.pub|*/known_hosts|*/known_hosts.old)
            chmod 644 "$f" ;;
          *)
            chmod 600 "$f" ;;
        esac
      done
    fi
    if [ -d "${homeDirectory}/.gnupg" ]; then
      ${pkgs.findutils}/bin/find "${homeDirectory}/.gnupg" -type d -exec chmod 700 {} +
      ${pkgs.findutils}/bin/find "${homeDirectory}/.gnupg" -type f -exec chmod 600 {} +
    fi

    # --- cursor-agent via the official installer ---
    if [ ! -x "${homeDirectory}/.local/bin/cursor-agent" ]; then
      export PATH="${
        lib.makeBinPath [
          pkgs.bash
          pkgs.coreutils
          pkgs.curl
          pkgs.gnutar
          pkgs.gzip
        ]
      }:$PATH"
      if ! "${pkgs.curl}/bin/curl" -fsS https://cursor.com/install | "${pkgs.bash}/bin/bash"; then
        echo "warning: cursor-agent install failed; will retry on next switch" >&2
      fi
    fi
  '';
in
{
  inherit script packages;
}
