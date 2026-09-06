# macbook: facts and imports only.
{
  inputs,
  pkgs,
  self,
  username,
  hostname,
  ...
}:
{
  imports = [
    ../../modules/common.nix
    inputs.sops-nix.darwinModules.sops
    ../../modules/security/sops.nix
    ../../modules/users/darwin.nix
    ./apps.nix
    ./defaults.nix
    ./homebrew.nix
    ./logitech
    ./mux
    ./muxd.nix
    ./services.nix
    ./startup
    ./voiceink
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

  security.pam.services.sudo_local.touchIdAuth = true;
}
