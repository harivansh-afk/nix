# The single definition of the nix.conf settings both hosts share.
#
# Two consumers, two mechanisms:
# - spark (NixOS): system/common.nix sets these as `nix.settings`.
# - macbook (darwin): Determinate Nix owns /etc/nix/nix.conf, so
#   flake/hosts.nix passes the same attrset as
#   `determinateNix.customSettings` (per AGENTS.md, nix.settings is not
#   the mechanism on darwin).
#
# Edit here and both hosts move together.
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
  cores = 0;

  # Pull prebuilt binaries (incl. neovim-nightly) from the nix-community
  # Cachix. Without this, uncached source builds of Rust packages run the
  # cargo-vendor fetcher, which crates.io now 403s for default User-Agents,
  # breaking `switch`. The vendored deps for those builds are already cached
  # here, so this skips the failing fetch entirely.
  extra-substituters = [ "https://nix-community.cachix.org" ];
  extra-trusted-public-keys = [
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  ];
}
