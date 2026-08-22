{ lib, pkgs }:
let
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

  packages = {
    ga = mkScript {
      name = "ga";
      file = ./bin/ga.sh;
      runtimeInputs = with pkgs; [ git ];
    };

    ghpr = mkScript {
      name = "ghpr";
      file = ./bin/ghpr.sh;
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
      file = ./bin/iosrun.sh;
      runtimeInputs = with pkgs; [
        findutils
        gnugrep
        coreutils
      ];
    };

    spark = mkScript {
      name = "spark";
      file = ./bin/spark.sh;
      runtimeInputs = with pkgs; [
        mosh
        openssh
      ];
    };
  };
in
{
  inherit mkScript packages;
}
