# macbook: facts and file selection only. Behavior lives in the sibling
# concern files (defaults / services / apps / homebrew) and shared modules.
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
    ./nap.nix
    ./voiceink.nix
    ./voiceink-cloud-model.nix
    ./voiceink-dictionary.nix
    ./apps.nix
    ./defaults.nix
    ./homebrew.nix
    ./services.nix
    ./startup-guard.nix
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
