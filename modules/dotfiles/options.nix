{
  inputs,
  hostConfig,
  username,
  lib,
  pkgs,
  ...
}:
let
  fileSubmodule = lib.types.submodule (
    { name, ... }:
    {
      options = {
        target = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = ''
            Target path. Either absolute (starting with /) or relative to
            the user's homeDirectory. Defaults to the attribute name.
          '';
        };
        source = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            Source path. Will be symlinked into target. Mutually exclusive
            with text.
          '';
        };
        text = lib.mkOption {
          type = lib.types.nullOr lib.types.lines;
          default = null;
          description = ''
            Content. Will be materialized via pkgs.writeText at activation
            time and symlinked into target. Mutually exclusive with source.
          '';
        };
        executable = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
        recursive = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            If true, source must be a directory and target is created as
            a real directory with one symlink per file inside source.
          '';
        };
        force = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            If true, overwrite existing real files without taking a
            timestamped backup.
          '';
        };
      };
    }
  );

  # Tool modules (added incrementally as Chunks 3+4 progress).
  toolModules = [
    ./tools/bat.nix
    ./tools/btop.nix
    ./tools/codex.nix
    ./tools/claude.nix
    ./tools/cursor-agent.nix
    ./tools/devin.nix
    ./tools/direnv.nix
    ./tools/eza.nix
    ./tools/fzf.nix
    ./tools/gcloud.nix
    ./tools/gh.nix
    ./tools/git.nix
    ./tools/ghostty.nix
    ./tools/helium.nix
    ./tools/k9s.nix
    ./tools/karabiner.nix
    ./tools/lazygit.nix
    ./tools/neovim.nix
    ./tools/prompt.nix
    ./tools/scripts.nix
    ./tools/security.nix
    ./tools/skills.nix
    ./tools/ssh.nix
    ./tools/tea.nix
    ./tools/tmux.nix
    ./tools/xdg.nix
    ./tools/zoxide.nix
    ./tools/zsh.nix
    ./tools/aerospace.nix
  ];

  baseModule =
    {
      name,
      config,
      lib,
      ...
    }:
    {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
        username = lib.mkOption {
          type = lib.types.str;
          default = name;
        };
        homeDirectory = lib.mkOption {
          type = lib.types.str;
        };
        group = lib.mkOption {
          type = lib.types.str;
          default = "users";
        };
        xdg = {
          configHome = lib.mkOption {
            type = lib.types.str;
          };
          stateHome = lib.mkOption {
            type = lib.types.str;
          };
          dataHome = lib.mkOption {
            type = lib.types.str;
          };
          cacheHome = lib.mkOption {
            type = lib.types.str;
          };
        };
        files = lib.mkOption {
          type = lib.types.attrsOf fileSubmodule;
          default = { };
        };
        dirs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        zshInit = lib.mkOption {
          type = lib.types.lines;
          default = "";
        };
        sessionVars = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
        };
        sessionPath = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
        };
        activationLines = lib.mkOption {
          type = lib.types.lines;
          default = "";
        };
      };

      config = {
        # Default xdg paths derived from homeDirectory. Override per-user
        # if you ever need non-standard XDG.
        xdg.configHome = lib.mkDefault "${config.homeDirectory}/.config";
        xdg.stateHome = lib.mkDefault "${config.homeDirectory}/.local/state";
        xdg.dataHome = lib.mkDefault "${config.homeDirectory}/.local/share";
        xdg.cacheHome = lib.mkDefault "${config.homeDirectory}/.cache";

        # Auto-derived per-user theme + paths, exposed to all tool modules.
        _module.args.paths = import ../../lib/paths.nix {
          homeDirectory = config.homeDirectory;
        };
        _module.args.theme = import ../../lib/theme.nix (
          import ../../lib/paths.nix { homeDirectory = config.homeDirectory; }
        );
      };
    };

  userSubmodule = lib.types.submoduleWith {
    shorthandOnlyDefinesConfig = false;
    specialArgs = {
      inherit
        inputs
        hostConfig
        username
        pkgs
        ;
    };
    modules = [ baseModule ] ++ toolModules;
  };
in
{
  options.dotfiles = {
    users = lib.mkOption {
      type = lib.types.attrsOf userSubmodule;
      default = { };
      description = ''
        Per-user dotfile state. Replaces home-manager. Each entry produces
        files in the user's $HOME plus optional shell init, packages, and
        activation work.
      '';
    };
  };
}
