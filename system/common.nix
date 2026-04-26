{
  inputs,
  lib,
  pkgs,
  username,
  hostConfig,
  ...
}:
let
  packageSets = import ../packages.nix { inherit inputs lib pkgs; };
in
{
  # Determinate Nix owns the Nix installation, the daemon, and
  # /etc/nix/nix.conf. On NixOS the determinate module redirects
  # /etc/nix/nix.conf to /etc/nix/nix.custom.conf, so anything we set via
  # `nix.settings` here ends up in the custom config. On darwin the
  # determinate nix-darwin module force-disables `nix.*` and expects
  # equivalents via `determinateNix.customSettings` (set in flake/macbook.nix).
  # Garbage collection is handled by determinate-nixd, so don't set nix.gc.
  nix.settings = {
    auto-optimise-store = true;
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      username
    ];
    use-xdg-base-directories = true;
    max-jobs = "auto";
    cores = 0;
  };

  nixpkgs.config.allowUnfree = true;
  # neovim-nightly's binary cache doesn't publish aarch64-linux, so on
  # spark it would rebuild nightly HEAD on every flake bump. Skip the
  # overlay there; `pkgs.neovim` from nixpkgs is fine. Gating on
  # `hostConfig` (not `pkgs.stdenv.hostPlatform`) avoids the infinite
  # recursion you get when reading pkgs to decide what pkgs should be.
  nixpkgs.overlays = lib.optionals (hostConfig.system != "aarch64-linux") [
    inputs.neovim-nightly.overlays.default
  ]
  # On darwin, pull nushell from a newer nixpkgs that adds the
  # `env_shlvl_in_(exec_)repl` test names to its darwin skip list.
  # Old nixpkgs's package recipe doesn't skip them and the tests
  # EPERM in the darwin sandbox. We don't bump our top-level nixpkgs
  # for this because it would invalidate the spark NVIDIA kernel hash.
  ++ lib.optionals hostConfig.isDarwin [
    (_final: _prev: {
      nushell = inputs.nixpkgs-nushell.legacyPackages.${hostConfig.system}.nushell;
    })
  ];

  programs.zsh.enable = true;
  environment.shells = [ pkgs.zsh ];

  environment.systemPackages =
    packageSets.core
    ++ lib.optionals hostConfig.isLinux [
      # Remote shells entered from Ghostty advertise TERM=xterm-ghostty.
      # Install Ghostty's terminfo entry on Linux hosts so SSH sessions
      # render and clear correctly.
      pkgs.ghostty.terminfo
    ];

  environment.variables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
}
