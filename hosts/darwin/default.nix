{
  pkgs,
  self,
  username,
  hostname,
  ...
}:
{
  imports = [
    ../../modules/base.nix
    ../../modules/macos.nix
    ../../modules/packages.nix
    ../../modules/homebrew.nix
  ];

  networking.hostName = hostname;

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
    shell = pkgs.zsh;
  };

  system.primaryUser = username;
  system.configurationRevision = self.rev or self.dirtyRev or null;
  system.stateVersion = 6;
}
