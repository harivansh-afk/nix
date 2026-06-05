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
  attr = "${pkgs.attr}/bin";
in
{
  home.file.".codex/AGENTS.md".source = ../dots/codex/AGENTS.md;

  home.activation.seedCodexConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    target="$HOME/.codex/config.toml"
    source="${codexConfigSource}"
    current=""

    ${coreutils}/mkdir -p "$HOME/.codex"

    if [ -e "$target" ] && [ ! -L "$target" ]; then
      if xattr_value="$(${attr}/getfattr --only-values -n "${xattrName}" "$target" 2>&1)"; then
        current="$xattr_value"
      fi
    fi

    if [ ! -e "$target" ] || [ -L "$target" ] || [ "$current" != "$source" ]; then
      tmp="$target.hm-seed-tmp"
      ${coreutils}/rm -f "$target" "$tmp"
      ${coreutils}/cp --no-preserve=ownership "$source" "$tmp"
      ${coreutils}/chmod u+w "$tmp"
      ${coreutils}/mv "$tmp" "$target"
      ${attr}/setfattr -n "${xattrName}" -v "$source" "$target"
    fi
  '';
}
