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

  remotes = import ../../lib/remotes.nix;

  remotePackages = lib.mapAttrs (
    name: host:
    mkScript {
      inherit name;
      file = ./bin/remote.sh;
      runtimeInputs = [
        pkgs.mosh
        pkgs.openssh
      ];
      replacements = {
        "@NAME@" = name;
        "@HOST@" = host;
      };
    }
  ) remotes;

  packages = {
    share = mkScript {
      name = "share";
      file = ./bin/share.sh;
      runtimeInputs = with pkgs; [
        coreutils
        curl
        findutils
        getopt
        jq
        openssh
        python3
      ];
      replacements = {
        "@UPLOADER@" = "${(import ../copyparty { inherit pkgs; }).uploader}/u2c.py";
        "@VERSION@" = (import ../copyparty { inherit pkgs; }).version;
      };
    };

    ga = mkScript {
      name = "ga";
      file = ./bin/ga.sh;
      runtimeInputs = with pkgs; [ git ];
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
  }
  // remotePackages;
in
{
  inherit mkScript packages;
}
