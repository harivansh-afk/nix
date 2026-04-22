{
  lib,
  hostConfig,
  ...
}:
{
  imports =
    [ ]
    ++ lib.optionals hostConfig.isDarwin [
      ./helium.nix
      ./aerospace.nix
      ./karabiner.nix
    ]
    ++ lib.optionals hostConfig.isLinux [
      ./worktree.nix
    ];
}
