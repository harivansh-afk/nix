{
  lib,
  pkgs,
  name,
  homeDirectory,
  configHome,
  dataHome,
  stateHome,
  coreutilsBin,
  dotsRoot,
  hostname,
  isDarwin,
  theme,
  customScripts,
  environmentD,
  zshenvShim,
  zshrcShim,
  zshThemes,
  gitCredentialsInc,
  fzfThemes,
  sketchybarThemes,
  ghosttyTerminfo,
  ghosttyThemes,
  claudeSettings,
  claudeMcpSource,
  piModels,
  claudeMd,
  codexAgentsMd,
  agentSkills,
  codexConfigSource,
  readXattr,
  writeXattr,
  teaLoginYaml,
  forgeLogins,
  heliumExtJson,
  heliumExtensions,
  rexDefaults,
  rexFont,
  rexThemes,
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

  mkdir -p \
    "${configHome}/zsh/themes" \
    "${configHome}/environment.d" \
    "${configHome}/git" \
    "${configHome}/jj" \
    "${configHome}/fzf/themes" \
    "${configHome}/ghostty/themes" \
    "${configHome}/direnv/lib" \
    "${configHome}/gh" \
    "${configHome}/npm" \
    "${configHome}/python" \
    "${configHome}/devin" \
    "${configHome}/tea" \
    "${homeDirectory}/.claude" \
    "${homeDirectory}/.agents" \
    "${homeDirectory}/.codex" \
    "${homeDirectory}/.local/bin" \
    "${homeDirectory}/.ssh/sockets" \
    "${stateHome}" \
    "${theme.paths.stateDir}" \
    "${theme.wallpapers.dir}"

  mkSymlink "${zshrcShim}" "${homeDirectory}/.zshrc"
  mkSymlink "${zshenvShim}" "${homeDirectory}/.zshenv"
  mkSymlink "${zshThemes.dark}" "${configHome}/zsh/themes/dark.zsh"
  mkSymlink "${zshThemes.light}" "${configHome}/zsh/themes/light.zsh"
  mkSymlink "${environmentD}" "${configHome}/environment.d/10-user-config.conf"

  mkSymlink "${dotsRoot}/git/config" "${configHome}/git/config"
  mkSymlink "${dotsRoot}/git/ignore" "${configHome}/git/ignore"
  mkSymlink "${dotsRoot}/git/allowed_signers" "${configHome}/git/allowed_signers"
  mkSymlink "${gitCredentialsInc}" "${configHome}/git/credentials.inc"

  mkSymlink "${dotsRoot}/jj/config.toml" "${configHome}/jj/config.toml"

  mkSymlink "${dotsRoot}/ssh/config" "${homeDirectory}/.ssh/config"

  ${lib.optionalString (!isDarwin) ''
    mkSymlink "${dotsRoot}/bin/open" "${homeDirectory}/.local/bin/open"
    mkdir -p "${homeDirectory}/.local/share/applications"
    mkSymlink "${dotsRoot}/bin/macbook-open" "${homeDirectory}/.local/bin/macbook-open"
    mkSymlink "${dotsRoot}/xdg/macbook-open.desktop" "${homeDirectory}/.local/share/applications/macbook-open.desktop"
    mkSymlink "${dotsRoot}/xdg/mimeapps.list" "${configHome}/mimeapps.list"
    mkSymlink "${dotsRoot}/bin/wl-paste" "${homeDirectory}/.local/bin/wl-paste"
    mkSymlink "${dotsRoot}/bin/xclip" "${homeDirectory}/.local/bin/xclip"
  ''}

  if [ -d "${configHome}/nvim" ] && [ ! -L "${configHome}/nvim" ]; then
    mv "${configHome}/nvim" "$(mktemp -d "${configHome}/nvim-backup.XXXXXX")/nvim"
  fi
  mkSymlink "${dotsRoot}/nvim" "${configHome}/nvim"

  mkSymlink "${dotsRoot}/direnv/direnv.toml" "${configHome}/direnv/direnv.toml"
  mkSymlink "${pkgs.nix-direnv}/share/nix-direnv/direnvrc" "${configHome}/direnv/lib/nix-direnv.sh"
  mkSymlink "${dotsRoot}/wgetrc" "${configHome}/wgetrc"
  mkSymlink "${dotsRoot}/npm/npmrc" "${configHome}/npm/npmrc"
  mkSymlink "${dotsRoot}/python/pythonrc" "${configHome}/python/pythonrc"
  mkSymlink "${dotsRoot}/ghostty/config" "${configHome}/ghostty/config"
  mkSymlink "${ghosttyThemes.dark}" "${configHome}/ghostty/themes/cozybox-dark"
  mkSymlink "${ghosttyThemes.light}" "${configHome}/ghostty/themes/cozybox-light"

  mkSymlink "${ghosttyTerminfo}/share/terminfo" "${homeDirectory}/.terminfo"
  mkSymlink "${fzfThemes.dark}" "${configHome}/fzf/themes/cozybox-dark"
  mkSymlink "${fzfThemes.light}" "${configHome}/fzf/themes/cozybox-light"

  rm -f "${configHome}/gh/config.yml"
  cp -f "${dotsRoot}/gh/config.yml" "${configHome}/gh/config.yml"
  chmod u+w "${configHome}/gh/config.yml"

  ${lib.optionalString (hostname == "spark") ''
    mkdir -p "${homeDirectory}/.agent-browser"
    mkSymlink "${dotsRoot}/agent-browser/config.json" "${homeDirectory}/.agent-browser/config.json"
  ''}
  rm -rf "${homeDirectory}/.claude/hooks"
  mkSymlink "${claudeMd}" "${homeDirectory}/.claude/CLAUDE.md"
  mkSymlink "${agentSkills}" "${homeDirectory}/.agents/skills"
  mkSymlink "${agentSkills}" "${homeDirectory}/.claude/skills"
  mkSymlink "${claudeSettings}" "${homeDirectory}/.claude/settings.json"
  ${lib.optionalString (piModels != null) ''
    mkdir -p "${homeDirectory}/.pi/agent"
    mkSymlink "${piModels}" "${homeDirectory}/.pi/agent/models.json"
  ''}

  ${lib.optionalString (claudeMcpSource != null) ''
    target="${homeDirectory}/.claude.json"
    tmp=$(mktemp "${homeDirectory}/.claude.json.XXXXXX")
    if [ -e "$target" ]; then
      ${pkgs.jq}/bin/jq --slurpfile servers ${claudeMcpSource} '.mcpServers = ((.mcpServers // {}) + $servers[0])' "$target" > "$tmp"
    else
      ${pkgs.jq}/bin/jq -n --slurpfile servers ${claudeMcpSource} '{mcpServers: $servers[0]}' > "$tmp"
    fi
    chmod 600 "$tmp"
    mv "$tmp" "$target"
  ''}
  mkSymlink "${dotsRoot}/claude/statusline.sh" "${homeDirectory}/.claude/statusline.sh"

  mkSymlink "${codexAgentsMd}" "${homeDirectory}/.codex/AGENTS.md"

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

  if [ -f "${configHome}/devin/config.json" ] \
    && ! ${pkgs.diffutils}/bin/cmp -s "${dotsRoot}/devin/config.json" "${configHome}/devin/config.json"; then
    timestamp="$(date +%Y%m%d%H%M%S)"
    cp "${configHome}/devin/config.json" "${configHome}/devin/config.json.bak.$timestamp"
  fi
  install -m 600 "${dotsRoot}/devin/config.json" "${configHome}/devin/config.json"

  harivanTokenFile=/run/secrets/forgejo-token

  harivanToken=
  if [ -r "$harivanTokenFile" ]; then
    harivanToken=$(cat "$harivanTokenFile")
  fi

  if [ -n "$harivanToken" ]; then
    install -d -m 0700 "${configHome}/tea"
    umask 077
    tmp="${configHome}/tea/config.yml.tmp"

    {
      printf '%s\n' "logins:"
      ${teaLoginYaml} harivan https://git.harivan.sh git.harivan.sh "$harivanToken" true ${lib.escapeShellArg forgeLogins.harivan}
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

  ${customScripts.themeAssetsText}

  mkdir -p "${theme.paths.stateDir}" \
           "${theme.paths.fzfDir}" \
           "${theme.paths.ghosttyDir}" \
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

  ln -sfn "$THEME_WALLPAPER" "${theme.wallpapers.current}"

  ${lib.optionalString isDarwin ''
    ghostty_appsupport="${homeDirectory}/Library/Application Support/com.mitchellh.ghostty"
    mkdir -p "$ghostty_appsupport"
    mkSymlink "${dotsRoot}/ghostty/config" "$ghostty_appsupport/config"


    mkSymlink "${dotsRoot}/karabiner" "${configHome}/karabiner"

    mkdir -p "${configHome}/aerospace"
    mkSymlink "${dotsRoot}/aerospace/aerospace.toml" "${configHome}/aerospace/aerospace.toml"

    mkdir -p "${theme.paths.sketchybarDir}"
    mkSymlink "${dotsRoot}/sketchybar/sketchybarrc" "${configHome}/sketchybar/sketchybarrc"
    mkSymlink "${sketchybarThemes.dark}" "${theme.paths.sketchybarDir}/cozybox-dark.sh"
    mkSymlink "${sketchybarThemes.light}" "${theme.paths.sketchybarDir}/cozybox-light.sh"
    ln -sfn "$THEME_SKETCHYBAR_TARGET" "${theme.paths.sketchybarCurrentFile}"

    mkdir -p "${configHome}/rex"
    mkSymlink "${dotsRoot}/rex/init.lua" "${configHome}/rex/init.lua"
    for rex_bin in "/Applications/Rex Beta.app/Contents/Helpers/Rex Server."{rex,app}"/Contents/MacOS/rex"; do
      if [ -x "$rex_bin" ]; then
        mkSymlink "$rex_bin" "${homeDirectory}/.local/bin/rex"
        break
      fi
    done
    ${rexFont} || echo "warning: rex font build failed" >&2
    rex_set() { /usr/bin/defaults write com.superlogical.rex "$@"; }
    rex_set Workspace.customThemes -data "$(od -An -v -tx1 ${rexThemes} | tr -d ' \n')"
    ${lib.concatStrings (
      lib.mapAttrsToList (key: value: ''
        rex_set Workspace.${key} ${
          if builtins.isBool value then
            "-bool ${lib.boolToString value}"
          else if builtins.isFloat value then
            "-float ${toString value}"
          else
            "-string ${lib.escapeShellArg value}"
        }
      '') rexDefaults
    )}
    if [ -x "$rex_bin" ]; then
      "$rex_bin" config reload --autostart=false >/dev/null 2>&1 || true
    fi

    helium_ext="${homeDirectory}/Library/Application Support/net.imput.helium/External Extensions"
    mkdir -p "$helium_ext"
    ${lib.concatMapStringsSep "\n" (id: ''
      mkSymlink "${heliumExtJson}" "$helium_ext/${id}.json"
    '') heliumExtensions}
  ''}

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

  rustup_bin="/run/current-system/sw/bin/rustup"
  rustc_bin="/run/current-system/sw/bin/rustc"
  if [ -x "$rustup_bin" ] && [ -x "$rustc_bin" ]; then
    export RUSTUP_HOME="${dataHome}/rustup"
    export CARGO_HOME="${dataHome}/cargo"
    rust_sysroot="$("$rustc_bin" --print sysroot 2>/dev/null || true)"
    if [ -n "$rust_sysroot" ] && [ ! -d "$rust_sysroot/lib/rustlib/src/rust/library" ]; then
      if ! "$rustup_bin" component add rust-src >/dev/null 2>&1; then
        echo "warning: rustup component add rust-src failed; rust-analyzer will not resolve std" >&2
      fi
    fi
  fi
''
