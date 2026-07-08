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

  remotes = import ../lib/remotes.nix;

  muxRemotesText = lib.concatMapStrings (
    name:
    let
      remote = remotes.${name};
    in
    "${name} ${remote.host}\n"
  ) (lib.attrNames remotes);

  remotePackages = lib.mapAttrs (
    name: remote:
    mkScript {
      inherit name;
      file = ./bin/remote.sh;
      runtimeInputs = [ pkgs.mosh ];
      replacements = {
        "@NAME@" = name;
        "@HOST@" = remote.host;
      };
    }
  ) remotes;

  packages = {
    mux = mkScript {
      name = "mux";
      file = ./bin/mux.sh;
      runtimeInputs =
        with pkgs;
        [
          coreutils
          fzf
          gawk
          git
          gnugrep
          gnused
          openssh
        ]
        ++ lib.optionals stdenv.isLinux [ util-linux ];
      replacements = {
        "@MUX_REMOTES@" = muxRemotesText;
      };
    };

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
  }
  // remotePackages;
in
{
  inherit mkScript packages;
}
