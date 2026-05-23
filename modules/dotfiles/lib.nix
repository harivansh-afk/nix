{ pkgs, lib }:
let
  cu = "${pkgs.coreutils}/bin";
  findBin = "${pkgs.findutils}/bin/find";
in
rec {
  # Resolve a target path against a user's home, supporting absolute targets.
  resolveTarget = home: target: if lib.hasPrefix "/" target then target else "${home}/${target}";

  # Materialize a file submodule entry into a source store path.
  # Returns null if neither source nor text is set.
  materialize =
    name: file:
    if file.source != null then
      file.source
    else if file.text != null then
      let
        # Sanitize the attr name so writeText/writeTextFile gets a clean basename.
        safeName = lib.replaceStrings [ "/" "." ] [ "_" "_" ] name;
      in
      if file.executable then
        pkgs.writeShellApplication {
          name = safeName;
          text = file.text;
          runtimeInputs = [ ];
        }
      else
        pkgs.writeText safeName file.text
    else
      null;

  # Idempotent install of one symlink target. Backs up pre-existing real
  # files once (with a timestamp suffix) unless `force` is set; replaces
  # any existing symlink unconditionally.
  mkInstallSnippet =
    {
      user,
      group,
      target,
      source,
      executable ? false,
      force ? false,
    }:
    let
      modeFlag = if executable then "755" else "644";
      quotedTarget = lib.escapeShellArg target;
      quotedSource = lib.escapeShellArg (toString source);
    in
    ''
      tgt=${quotedTarget}
      src=${quotedSource}
      parent="$(${cu}/dirname "$tgt")"
      ${cu}/install -d -o ${lib.escapeShellArg user} -g ${lib.escapeShellArg group} "$parent"
      if [ -L "$tgt" ]; then
        ${cu}/ln -sfnT "$src" "$tgt"
      elif [ ! -e "$tgt" ]; then
        ${cu}/ln -sfnT "$src" "$tgt"
      ${
        if force then
          ''
            else
              ${cu}/rm -rf "$tgt"
              ${cu}/ln -sfnT "$src" "$tgt"
          ''
        else
          ''
            else
              ts="$(${cu}/date +%Y%m%d%H%M%S)"
              ${cu}/mv "$tgt" "$tgt.bak.$ts"
              ${cu}/ln -sfnT "$src" "$tgt"
          ''
      }
      fi
      ${cu}/chown -h ${lib.escapeShellArg "${user}:${group}"} "$tgt"
      # mode is recorded for documentation; symlink itself is 777 on disk
      true # ${modeFlag}
    '';

  # Recursive symlink farm: target is a real directory, each file inside
  # source is symlinked into the corresponding path inside target. Matches
  # home-manager's xdg.configFile.X.recursive = true.
  mkRecursiveInstallSnippet =
    {
      user,
      group,
      target,
      source,
    }:
    ''
      tgt=${lib.escapeShellArg target}
      src=${lib.escapeShellArg (toString source)}
      ${cu}/install -d -o ${lib.escapeShellArg user} -g ${lib.escapeShellArg group} "$tgt"
      ${findBin} "$src" -mindepth 1 -type f -print0 | while IFS= read -r -d "" f; do
        rel="''${f#"$src/"}"
        link="$tgt/$rel"
        link_parent="$(${cu}/dirname "$link")"
        ${cu}/install -d -o ${lib.escapeShellArg user} -g ${lib.escapeShellArg group} "$link_parent"
        if [ -L "$link" ] || [ ! -e "$link" ]; then
          ${cu}/ln -sfnT "$f" "$link"
        else
          ts="$(${cu}/date +%Y%m%d%H%M%S)"
          ${cu}/mv "$link" "$link.bak.$ts"
          ${cu}/ln -sfnT "$f" "$link"
        fi
        ${cu}/chown -h ${lib.escapeShellArg "${user}:${group}"} "$link"
      done
    '';

  # mkdir -p -ish for a path that may be relative or absolute.
  mkDirSnippet =
    {
      user,
      group,
      path,
    }:
    ''
      ${cu}/install -d -o ${lib.escapeShellArg user} -g ${lib.escapeShellArg group} ${lib.escapeShellArg path}
    '';

  # Build the full per-user installation script body. Pure shell, no
  # privilege escalation - the platform layer wraps this in runuser/su
  # on linux or runs it under postUserActivation on darwin.
  buildUserScript =
    userCfg:
    let
      home = userCfg.homeDirectory;
      user = userCfg.username;
      group = userCfg.group;
      resolvedDirs = map (p: resolveTarget home p) userCfg.dirs;
      dirSnippets = lib.concatMapStringsSep "\n" (
        path:
        mkDirSnippet {
          inherit user group path;
        }
      ) resolvedDirs;
      fileSnippets = lib.concatMapStringsSep "\n" (
        entry:
        let
          name = entry.name;
          file = entry.value;
          src = materialize name file;
          target = resolveTarget home file.target;
        in
        if src == null then
          ""
        else if file.recursive then
          mkRecursiveInstallSnippet {
            inherit user group target;
            source = src;
          }
        else
          mkInstallSnippet {
            inherit user group target;
            source = src;
            inherit (file) executable force;
          }
      ) (lib.mapAttrsToList lib.nameValuePair userCfg.files);
    in
    ''
      set -euo pipefail
      ${dirSnippets}
      ${fileSnippets}
      ${userCfg.activationLines}
    '';
}
