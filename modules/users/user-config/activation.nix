# The per-user activation script. This is the one place bash lives: it
# materialises every symlink, seeds the writable configs, renders secrets
# into place, and initialises theme state. Everything it references is a
# store path or string computed by the sibling modules.
{
  lib,
  pkgs,
  name,
  homeDirectory,
  configHome,
  stateHome,
  coreutilsBin,
  dotsRoot,
  isDarwin,
  theme,
  customScripts,
  environmentD,
  zshenvShim,
  zshrcShim,
  zshThemes,
  gitCredentialsInc,
  gitDeltaThemesInc,
  btopConf,
  fzfThemes,
  ghosttyThemes,
  lazygitConfigs,
  claudeSettings,
  codexConfigSource,
  readXattr,
  writeXattr,
  ompThemes,
  ompConfigSource,
  ompModesSource,
  ompMcpSource,
  ompReadXattr,
  ompWriteXattr,
  teaLoginYaml,
  forgeLogins,
  heliumExtJson,
  heliumExtensions,
  ...
}:
pkgs.writeShellScript "user-config-${name}" ''
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
    "${configHome}/ghostty/shaders" \
    "${configHome}/ghostty/themes" \
    "${configHome}/lazygit" \
    "${configHome}/direnv/lib" \
    "${configHome}/k9s" \
    "${configHome}/gh" \
    "${configHome}/graphite" \
    "${configHome}/npm" \
    "${configHome}/python" \
    "${configHome}/btop" \
    "${configHome}/devin" \
    "${configHome}/gcloud/configurations" \
    "${configHome}/tea" \
    "${homeDirectory}/.claude/hooks" \
    "${homeDirectory}/.codex" \
    "${homeDirectory}/.omp/agent/themes" \
    "${homeDirectory}/.omp/agent/extensions" \
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

  # --- bin: standalone helper scripts ---
  mkSymlink "${dotsRoot}/bin/pasteimg" "${homeDirectory}/.local/bin/pasteimg"
  ${lib.optionalString (!isDarwin) ''
    mkdir -p "${homeDirectory}/.local/share/applications"
    mkSymlink "${dotsRoot}/bin/open" "${homeDirectory}/.local/bin/open"
    mkSymlink "${dotsRoot}/bin/macbook-open" "${homeDirectory}/.local/bin/macbook-open"
    mkSymlink "${dotsRoot}/xdg/macbook-open.desktop" "${homeDirectory}/.local/share/applications/macbook-open.desktop"
    mkSymlink "${dotsRoot}/xdg/mimeapps.list" "${configHome}/mimeapps.list"
  ''}

  # --- nvim: keep the config directory writable for vim.pack's lockfile,
  # while symlinking every managed config entry from the dotfiles tree.
  if [ -d "${configHome}/nvim" ] && [ ! -L "${configHome}/nvim" ]; then
    for lock in lazy-lock.json nvim-pack-lock.json; do
      if [ -f "${configHome}/nvim/$lock" ] && [ ! -L "${configHome}/nvim/$lock" ] \
        && [ -w "${dotsRoot}/nvim" ] && [ ! -e "${dotsRoot}/nvim/$lock" ]; then
        cp "${configHome}/nvim/$lock" "${dotsRoot}/nvim/$lock"
      fi
    done
  fi
  if [ -L "${configHome}/nvim" ]; then
    rm -f "${configHome}/nvim"
  fi
  mkdir -p "${configHome}/nvim"
  # drop managed links from earlier generations so removed dots entries
  # do not linger
  for entry in "${configHome}/nvim"/* "${configHome}/nvim"/.[!.]* "${configHome}/nvim"/..?*; do
    if [ -L "$entry" ]; then
      rm -f "$entry"
    fi
  done
  for source in "${dotsRoot}/nvim"/* "${dotsRoot}/nvim"/.[!.]* "${dotsRoot}/nvim"/..?*; do
    [ -e "$source" ] || continue
    name="''${source##*/}"
    case "$name" in
      lazy-lock.json|nvim-pack-lock.json)
        if [ -w "${dotsRoot}/nvim" ]; then
          mkSymlink "$source" "${configHome}/nvim/$name"
        else
          install -m 0644 "$source" "${configHome}/nvim/$name"
        fi
        ;;
      *)
        mkSymlink "$source" "${configHome}/nvim/$name"
        ;;
    esac
  done

  # --- assorted app configs ---
  mkSymlink "${btopConf}" "${configHome}/btop/btop.conf"
  mkSymlink "${dotsRoot}/k9s/views.yaml" "${configHome}/k9s/views.yaml"
  mkSymlink "${dotsRoot}/direnv/direnv.toml" "${configHome}/direnv/direnv.toml"
  mkSymlink "${pkgs.nix-direnv}/share/nix-direnv/direnvrc" "${configHome}/direnv/lib/nix-direnv.sh"
  mkSymlink "${dotsRoot}/wgetrc" "${configHome}/wgetrc"
  mkSymlink "${dotsRoot}/npm/npmrc" "${configHome}/npm/npmrc"
  mkSymlink "${dotsRoot}/python/pythonrc" "${configHome}/python/pythonrc"
  mkSymlink "${dotsRoot}/ghostty/config" "${configHome}/ghostty/config"
  mkSymlink "${dotsRoot}/ghostty/shaders" "${configHome}/ghostty/shaders"
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

  mkSymlink "${ompThemes.dark}" "${homeDirectory}/.omp/agent/themes/cozybox-dark.json"
  mkSymlink "${ompThemes.light}" "${homeDirectory}/.omp/agent/themes/cozybox-light.json"
  mkSymlink "${ompModesSource}" "${homeDirectory}/.omp/agent/modes.json"
  mkSymlink "${ompMcpSource}" "${homeDirectory}/.omp/agent/mcp.json"
  mkSymlink "${dotsRoot}/omp/extensions/modes.ts" "${homeDirectory}/.omp/agent/extensions/modes.ts"
  mkSymlink "${dotsRoot}/omp/extensions/claude-hooks.ts" "${homeDirectory}/.omp/agent/extensions/claude-hooks.ts"
  mkSymlink "${dotsRoot}/omp/extensions/claude-agents.ts" "${homeDirectory}/.omp/agent/extensions/claude-agents.ts"
  rm -f "${homeDirectory}/.omp/agent/extensions/rich-diff.ts"
  mkSymlink "${dotsRoot}/omp/extensions/diffs/diffs.ts" "${homeDirectory}/.omp/agent/extensions/diffs.ts"
  mkSymlink "${dotsRoot}/omp/extensions/claude-purple/claude-purple.ts" "${homeDirectory}/.omp/agent/extensions/claude-purple.ts"

  target="${homeDirectory}/.omp/agent/config.yml"
  source="${ompConfigSource}"
  current=""

  if [ -e "$target" ] && [ ! -L "$target" ]; then
    if xattr_value="$(${ompReadXattr})"; then
      current="$xattr_value"
    fi
  fi

  if [ ! -e "$target" ] || [ -L "$target" ] || [ "$current" != "$source" ]; then
    tmp="$target.seed-tmp"
    rm -f "$target" "$tmp"
    cp "$source" "$tmp"
    chmod u+w "$tmp"
    mv "$tmp" "$target"
    ${ompWriteXattr}
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

  graphiteToken=
  graphiteEnvFile=/run/secrets/graphite.env
  if [ -r "$graphiteEnvFile" ]; then
    graphiteToken=$(
      set -a
      . "$graphiteEnvFile"
      printf '%s' "''${GRAPHITE_AUTH_TOKEN:-}"
    )
  fi

  if [ -n "$graphiteToken" ]; then
    umask 077
    tmp="${configHome}/graphite/auth.tmp"
    printf '%s' "$graphiteToken" | \
      ${pkgs.python3}/bin/python3 -c 'import json, sys; print(json.dumps({"authToken": sys.stdin.read()}), end="")' \
      > "$tmp"
    mv "$tmp" "${configHome}/graphite/auth"
    umask 022
  fi

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
        ${teaLoginYaml} harivan https://git.harivan.sh git.harivan.sh "$harivanToken" true ${lib.escapeShellArg forgeLogins.harivan}
      fi
      if [ -n "$ixToken" ]; then
        if [ -n "$harivanToken" ]; then
          ixDefault=false
        else
          ixDefault=true
        fi
        ${teaLoginYaml} ix-harivansh https://git.ix.dev git.ix.dev "$ixToken" "$ixDefault" ${lib.escapeShellArg forgeLogins.ix}
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
    mkSymlink "${dotsRoot}/ghostty/shaders" "$ghostty_appsupport/shaders"

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

  export PATH="${
    lib.makeBinPath [
      pkgs.bash
      pkgs.coreutils
      pkgs.curl
      pkgs.gnugrep
      pkgs.gnused
    ]
  }:$PATH"
  if [ ! -x "${homeDirectory}/.local/bin/omp" ]; then
    if ! "${pkgs.curl}/bin/curl" -fsSL https://omp.sh/install \
      | PI_INSTALL_DIR="${homeDirectory}/.local/bin" "${pkgs.bash}/bin/bash"; then
      echo "warning: omp install failed; will retry on next switch" >&2
    fi
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
''
