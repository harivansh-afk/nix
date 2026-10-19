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

      tools = pkgs.buildEnv {
        name = "portable-tools";
        paths = [
          nvim
        ]
        ++ (with pkgs; [
          bat
          btop
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
        inherit (pkgs) btop;
        inherit nvim tools;
      };
    };
}
