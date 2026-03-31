{
  lib,
  hostConfig,
  ...
}:
{
  imports =
    [
      ./common.nix
    ]
    ++ lib.optionals hostConfig.isDarwin [
      ./colima.nix
      ./rectangle.nix
      ./karabiner.nix
    ]
    ++ lib.optionals hostConfig.isLinux [
      ./netty-worktree.nix
    ];
}
