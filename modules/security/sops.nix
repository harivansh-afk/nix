# Central sops-nix wiring.
#
# Reads secrets/registry.nix and declares every secret that applies to this
# host. Imported by both nix-darwin and NixOS hosts. The platform-specific
# sops-nix module (darwin vs nixos) is imported by each host config — this
# file only needs to be platform-aware for the age key path.
{
  config,
  hostConfig,
  hostname,
  inputs,
  lib,
  username,
  ...
}:
let
  # Pass `inputs` so registry entries can override `sopsFile` to point
  # at an encrypted file shipped by another flake (e.g. inputs.symphony
  # for symphony.env). The merge in mapAttrs below already lets a
  # registry entry override any default we set per-secret.
  registry = import ../../secrets/registry.nix { inherit username inputs; };

  userSecrets = lib.mapAttrs (
    name: cfg:
    {
      sopsFile = ../../secrets/user + "/${name}";
      format = "binary";
      owner = username;
      mode = "0400";
    }
    // cfg
  ) registry.user;

  hostRegistry = registry.hosts.${hostname} or { };

  hostSecrets = lib.mapAttrs (
    name: cfg:
    {
      sopsFile = ../../secrets/hosts + "/${hostname}/${name}";
      format = "binary";
    }
    // cfg
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
