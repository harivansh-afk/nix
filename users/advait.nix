{
  sshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDiFzmTnNxyE31PxI53FdUuVEC4QgOxvAfr2nFdYiQ/p advait@companion.ai spark"
  ];
  shell = "zsh";
  extraGroups = [
    "video"
    "podman"
  ];
  linger = true;
}
