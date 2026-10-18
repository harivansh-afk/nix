{ lib, ... }:
{
  perSystem =
    { pkgs, inputs', ... }:
    let
      portableScripts = (import ../pkgs/scripts/portable.nix { inherit lib pkgs; }).packages;

      nvimPackages = import ../lib/nvim-packages.nix { inherit lib pkgs; };

      nvim = import ../lib/neovim.nix {
        inherit lib pkgs;
        neovim = inputs'.neovim-nightly.packages.default;
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

      btopConf = pkgs.writeText "btop-portable.conf" ''
        custom_cpu_name = "@HOSTNAME@"
        rounded_corners = False
        theme_background = False
        vim_keys = True
      '';

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
