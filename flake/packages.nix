# Flake packages: the portable scripts (ga, the per-remote
# connectors) plus portable, config-carrying tool wrappers. `nix run
# .#<name>` (or, from any machine,
# `nix run git+https://git.harivan.sh/harivansh-afk/nix.git#<name>`)
# launches the tool with this repo's config, no host activation layer
# required. `nix shell <flake>#tools` (or `nix profile install`) drops the
# whole everyday CLI set into a fresh VM in one command.
{ lib, ... }:
{
  perSystem =
    { pkgs, inputs', ... }:
    let
      portableScripts = (import ../pkgs/scripts/portable.nix { inherit lib pkgs; }).packages;

      nvimPackages = import ../lib/nvim-packages.nix { inherit lib pkgs; };

      nvim = import ../lib/neovim.nix {
        inherit lib pkgs;
        configDir = ../dots/nvim;
        extraPackages = nvimPackages;
      };

      lazygit = pkgs.writeShellApplication {
        name = "lazygit";
        runtimeInputs = [
          pkgs.lazygit
          pkgs.git
        ];
        text = ''
          exec lazygit --use-config-file ${../dots/lazygit/config.yml} "$@"
        '';
      };

      # Same template as btopConf in apps.nix, with the hostname substituted
      # at launch instead of at activation.
      btopConf = pkgs.writeText "btop-portable.conf" ''
        custom_cpu_name = "@HOSTNAME@"
        rounded_corners = False
        theme_background = False
        vim_keys = True
      '';

      # btop has no config-path flag and rewrites its config on exit, so it
      # gets a private writable XDG_CONFIG_HOME, seeded once and left alone
      # afterwards so in-app setting changes survive relaunches.
      btop = pkgs.writeShellApplication {
        name = "btop";
        runtimeInputs = [
          pkgs.btop
          pkgs.coreutils
          pkgs.gnused
        ];
        text = ''
          config_home="''${XDG_STATE_HOME:-$HOME/.local/state}/btop-portable"
          mkdir -p "$config_home/btop"
          if [ ! -f "$config_home/btop/btop.conf" ]; then
            sed "s/@HOSTNAME@/$(uname -n)/" ${btopConf} > "$config_home/btop/btop.conf"
          fi
          XDG_CONFIG_HOME="$config_home" exec btop "$@"
        '';
      };

      # The everyday CLI set from the pkgs/sets.nix base list, with the
      # wrapped tools above in place of the bare packages, plus the portable
      # scripts (ga, per-remote shortcuts) that are already flake
      # packages individually.
      tools = pkgs.buildEnv {
        name = "portable-tools";
        paths = [
          btop
          lazygit
          nvim
        ]
        ++ (with pkgs; [
          bat
          direnv
          eza
          fd
          fzf
          gh
          git
          git-lfs
          ripgrep
          tea
        ])
        ++ builtins.attrValues portableScripts;
      };
    in
    {
      packages = portableScripts // {
        cli-proxy-api = inputs'.cc-proxy.packages.cli-proxy-api;
        claude-proxy = inputs'.cc-proxy.packages.default;
        cbridge = inputs'.cc-proxy.packages.default;
        cc-proxy = inputs'.cc-proxy.packages.default;
        baml-cli = pkgs.callPackage ../pkgs/baml-cli { };
        sharefs = inputs'.sharefs.packages.default;
        devin-codex = inputs'.devin-codex.packages.default;
        inherit
          btop
          lazygit
          nvim
          tools
          ;
      };
    };
}
