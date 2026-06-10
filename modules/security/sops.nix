# Central sops-nix wiring.
#
# Reads secrets/registry.nix and declares every secret that applies to this
# host. Imported by both nix-darwin and NixOS hosts. The platform-specific
# sops-nix module (darwin vs nixos) is imported by each host config — this
# file only needs to be platform-aware for the age key path.
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
    let
      secretCfg = builtins.removeAttrs cfg [ "exposeToShell" ];
    in
    {
      sopsFile = ../../secrets/user + "/${name}";
      format = "binary";
      owner = username;
      mode = "0400";
    }
    // secretCfg
  ) registry.user;

  hostRegistry = registry.hosts.${hostname} or { };

  hostSecrets = lib.mapAttrs (
    name: cfg:
    let
      secretCfg = builtins.removeAttrs cfg [ "exposeToShell" ];
    in
    {
      sopsFile = ../../secrets/hosts + "/${hostname}/${name}";
      format = "binary";
    }
    // secretCfg
  ) hostRegistry;
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
