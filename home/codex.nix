{
  lib,
  pkgs,
  ...
}:
let
  # Immutable source for the managed Codex defaults. Codex rewrites
  # ~/.codex/config.toml at runtime (hook trust via the hooks.state key,
  # per-project trust_level, model NUX counters), so it cannot be a read-only
  # nix-store symlink: its config/batchWrite would fail with
  # "config/batchWrite failed while updating hook trust in TUI". Seed it as a
  # writable copy instead, and only reseed when this source store path changes
  # so runtime mutations (trusted hooks) survive every home-manager switch.
  codexConfigSource = ../dots/codex/config.toml;
  xattrName = "user.hari.codex-seed-source";
  coreutils = "${pkgs.coreutils}/bin";

  # Extended-attribute tooling differs per platform: Linux uses the `attr`
  # package (getfattr/setfattr), macOS ships its own BSD `xattr` at /usr/bin
  # and has no `attr` package (it is Linux-only, so referencing pkgs.attr on
  # darwin fails evaluation). Branch the read/write helpers accordingly.
  readXattr =
    if pkgs.stdenv.isDarwin then
      ''/usr/bin/xattr -p "${xattrName}" "$target" 2>/dev/null''
    else
      ''${pkgs.attr}/bin/getfattr --only-values -n "${xattrName}" "$target" 2>/dev/null'';
  writeXattr =
    if pkgs.stdenv.isDarwin then
      ''/usr/bin/xattr -w "${xattrName}" "$source" "$target"''
    else
      ''${pkgs.attr}/bin/setfattr -n "${xattrName}" -v "$source" "$target"'';
in
{
  # ~/.codex/AGENTS.md is owned by agent-context.nix, generated from
  # dots/agent-context/sections (same always-on core as ~/.claude/CLAUDE.md).
  home.activation.seedCodexConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    target="$HOME/.codex/config.toml"
    source="${codexConfigSource}"
    current=""

    ${coreutils}/mkdir -p "$HOME/.codex"

    if [ -e "$target" ] && [ ! -L "$target" ]; then
      if xattr_value="$(${readXattr})"; then
        current="$xattr_value"
      fi
    fi

    if [ ! -e "$target" ] || [ -L "$target" ] || [ "$current" != "$source" ]; then
      tmp="$target.hm-seed-tmp"
      ${coreutils}/rm -f "$target" "$tmp"
      ${coreutils}/cp --no-preserve=ownership "$source" "$tmp"
      ${coreutils}/chmod u+w "$tmp"
      ${coreutils}/mv "$tmp" "$target"
      ${writeXattr}
    fi
  '';
}
