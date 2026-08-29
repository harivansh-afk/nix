# sops-nix wiring for both platforms, driven by secrets/registry.nix.
{
  hostConfig,
  hostname,
  lib,
  username,
  ...
}:
let
  registry = import ../../secrets/registry.nix { inherit username; };

  userSecrets = lib.mapAttrs (
    name: cfg:
    {
      sopsFile = ../../secrets/user + "/${name}";
      format = "binary";
      owner = username;
      mode = "0400";
    }
    // builtins.removeAttrs cfg [ "exposeToShell" ]
  ) registry.user;

  hostSecrets = lib.mapAttrs (
    name: cfg:
    {
      sopsFile = ../../secrets/hosts + "/${hostname}/${name}";
      format = "binary";
    }
    // cfg
  ) (registry.hosts.${hostname} or { });
in
{
  sops = {
    age = {
      generateKey = false;
      sshKeyPaths =
        if hostConfig.isDarwin then
          [ "/Users/${username}/.ssh/id_ed25519" ]
        else
          [ "/etc/ssh/ssh_host_ed25519_key" ];
    };
    secrets = userSecrets // hostSecrets;
  };
}
