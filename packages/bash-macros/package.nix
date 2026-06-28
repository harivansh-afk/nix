# bash-macros: small everyday shell-macro CLIs, bundled into one derivation so
# they ride onto PATH together. Each .sh is shellcheck-linted at build time by
# writeShellApplication.
#   ga      - stage + status helper
#   ghpr    - GitHub PR helper
#   iosrun  - iOS simulator run helper
{
  pkgs,
  lib,
  ...
}:
let
  inherit (import ../lib.nix { inherit pkgs lib; }) mkScript;

  ga = mkScript {
    name = "ga";
    file = ./ga.sh;
    runtimeInputs = [ pkgs.git ];
  };
  ghpr = mkScript {
    name = "ghpr";
    file = ./ghpr.sh;
    runtimeInputs = with pkgs; [
      gh
      git
      gnugrep
      gnused
      coreutils
    ];
  };
  iosrun = mkScript {
    name = "iosrun";
    file = ./iosrun.sh;
    runtimeInputs = with pkgs; [
      findutils
      gnugrep
      coreutils
    ];
  };

  bundle = pkgs.symlinkJoin {
    name = "bash-macros";
    paths = [
      ga
      ghpr
      iosrun
    ];
    meta.description = "Small shell-macro CLIs: ga, ghpr, iosrun";
  };
in
{
  id = "bash-macros";
  platforms = [
    "aarch64-linux"
    "aarch64-darwin"
    "x86_64-linux"
  ];
  package = bundle;
  tests.smoke = pkgs.runCommand "bash-macros-smoke" { } ''
    for b in ga ghpr iosrun; do
      test -x ${bundle}/bin/"$b" || { echo "bash-macros: missing $b" >&2; exit 1; }
    done
    touch $out
  '';
}
