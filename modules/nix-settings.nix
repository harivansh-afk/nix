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

  extra-substituters = [ "https://nix-community.cachix.org" ];
  extra-trusted-public-keys = [
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  ];
}
