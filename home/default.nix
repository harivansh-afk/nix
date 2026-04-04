{
  lib,
  hostConfig,
  ...
}:
{
  imports = [
    ./common.nix
  ]
  ++ lib.optionals hostConfig.isDarwin [
    ./colima.nix
    ./helium.nix
    ./rectangle.nix
    ./karabiner.nix
  ]
  ++ lib.optionals hostConfig.isLinux [
    ./netty-worktree.nix
  ];
}
