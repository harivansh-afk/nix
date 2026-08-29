# nix.conf settings shared by both hosts: `nix.settings` on spark,
# `determinateNix.customSettings` on macbook (Determinate owns nix.conf there).
username: {
  auto-optimise-store = true;
  experimental-features = [
    "nix-command"
    "flakes"
    "ca-derivations"
  ];
  trusted-users = [
    "root"
    username
  ];
  use-xdg-base-directories = true;
  max-jobs = "auto";

  # nix-community cache: neovim-nightly and the Rust vendored deps whose
  # crates.io fetch otherwise 403s.
  extra-substituters = [ "https://nix-community.cachix.org" ];
  extra-trusted-public-keys = [
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  ];
}
