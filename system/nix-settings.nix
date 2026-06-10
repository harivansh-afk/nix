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
  ];
  trusted-users = [
    "root"
    username
  ];
  use-xdg-base-directories = true;
  max-jobs = "auto";
  cores = 0;
}
