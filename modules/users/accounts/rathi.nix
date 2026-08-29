{
  sshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM6tzq33IQcurWoQ7vhXOTLjv8YkdTGb7NoNsul3Sbfu rathi@mac"
  ];
  shell = "zsh";
  linger = true;
  extraGroups = [
    "wheel"
    "networkmanager"
    "video"
    "podman"
  ];
}
