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

  # Shared "name host" catalog lines, baked into mux (@MUX_REMOTES@) and
  # hrd (@HRD_REMOTES@).
  remotesText = lib.concatMapStrings (
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
      runtimeInputs = [
        pkgs.mosh
        pkgs.openssh
      ];
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
          zoxide
        ]
        ++ lib.optionals stdenv.isLinux [ util-linux ];
      replacements = {
        "@MUX_REMOTES@" = remotesText;
      };
    };

    hrd = mkScript {
      name = "hrd";
      file = ./bin/hrd.sh;
      runtimeInputs =
        with pkgs;
        [
          coreutils
          gawk
          jq
          mosh
          openssh
        ]
        ++ lib.optionals stdenv.isLinux [ util-linux ];
      replacements = {
        "@HRD_REMOTES@" = remotesText;
      };
    };

    fork = mkScript {
      name = "fork";
      file = ./bin/fork.sh;
      # herdr and the agent binaries (claude, codex, omp) resolve from the
      # user PATH on purpose: herdr is the nix input's bin, the agents are
      # installer-managed in ~/.local/bin.
      runtimeInputs =
        with pkgs;
        [
          coreutils
          gnugrep
          jq
        ]
        ++ lib.optionals stdenv.isLinux [ util-linux ]; # uuidgen (darwin: /usr/bin)
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
