# Shared helpers for packages/. mkScript wraps a shell file in
# writeShellApplication (which shellcheck-lints it at build time) with optional
# @PLACEHOLDER@ substitutions. Mirrors the helper in scripts/default.nix; the
# theme/wallpaper scripts there will fold onto this in a later pass.
{ pkgs, lib }:
{
  mkScript =
    {
      file,
      name,
      runtimeInputs ? [ ],
      replacements ? { },
    }:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = lib.replaceStrings (builtins.attrNames replacements) (builtins.attrValues replacements) (
        builtins.readFile file
      );
    };
}
