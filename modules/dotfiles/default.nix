{ hostConfig, ... }:
{
  imports = [
    ./options.nix
    (if hostConfig.isDarwin then ./platform/darwin.nix else ./platform/linux.nix)
  ];
}
