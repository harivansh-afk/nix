# Portable, config-carrying tool wrappers: `nix run .#<name>` (or, from any
# machine, `nix run git+https://git.harivan.sh/harivansh-afk/nix.git#<name>`)
# launches the tool with this repo's config, no host activation layer
# required. `nix shell <flake>#tools` (or `nix profile install`) drops the
# whole everyday CLI set into a fresh VM in one command.
{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      nvimPackages = import ../lib/nvim-packages.nix { inherit lib pkgs; };

      # renderLazygit only emits colors; homeDirectory feeds the other
      # renderers, so the placeholder is never dereferenced here.
      theme = import ../lib/theme.nix { homeDirectory = "/homeless-shelter"; };

      # vim.pack needs a writable config dir for its lockfile, so the wrapper
      # reseeds a copy of dots/nvim under $XDG_CONFIG_HOME/nvim-portable on
      # every launch: the committed nvim-pack-lock.json stays authoritative,
      # and NVIM_APPNAME scopes data/state/cache away from any resident nvim
      # install. Plugins clone themselves into that scoped data dir on first
      # run (network + git, both on the wrapper PATH).
      nvim = pkgs.writeShellApplication {
        name = "nvim";
        runtimeInputs = [ pkgs.neovim ] ++ nvimPackages;
        text = ''
          config_root="''${XDG_CONFIG_HOME:-$HOME/.config}"
          config_dir="$config_root/nvim-portable"
          rm -rf "$config_dir"
          mkdir -p "$config_root"
          cp -R ${../dots/nvim} "$config_dir"
          chmod -R u+w "$config_dir"
          export NVIM_APPNAME=nvim-portable
          exec nvim "$@"
        '';
      };

      # Same base-plus-theme concatenation as lazygitConfigs in
      # modules/users/user-config/apps.nix, pinned to dark mode: the portable
      # target is a headless VM shell, not a mode-switching desktop.
      lazygitConfig = pkgs.writeText "lazygit-portable.yml" (
        builtins.readFile ../dots/lazygit/config.yml + theme.renderLazygit "dark"
      );

      lazygit = pkgs.writeShellApplication {
        name = "lazygit";
        runtimeInputs = [
          pkgs.lazygit
          pkgs.git
          pkgs.delta
        ];
        text = ''
          exec lazygit --use-config-file ${lazygitConfig} "$@"
        '';
      };

      # Same template as btopConf in apps.nix, with the hostname substituted
      # at launch instead of at activation.
      btopConf = pkgs.writeText "btop-portable.conf" ''
        color_theme = "ayu"
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

      # The everyday CLI set from packages.nix base list, with the wrapped
      # tools above in place of the bare packages, plus the portable scripts
      # (mux, ga, ghpr, per-remote shortcuts) that are already flake packages
      # individually.
      tools = pkgs.buildEnv {
        name = "portable-tools";
        paths =
          [
            btop
            lazygit
            nvim
          ]
          ++ (with pkgs; [
            bat
            delta
            direnv
            eza
            fd
            fzf
            gh
            git
            git-lfs
            k9s
            ripgrep
            tea
          ])
          ++ builtins.attrValues (import ../scripts/portable.nix { inherit lib pkgs; }).packages;
      };
    in
    {
      packages = {
        inherit
          btop
          lazygit
          nvim
          tools
          ;
      };
    };
}
