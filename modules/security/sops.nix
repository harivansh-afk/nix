{ inputs, ... }:
let
  mkHostSecret =
    hostName: name: attrs:
    {
      sopsFile = ../../secrets/${hostName}/${name};
      format = "binary";
    }
    // attrs;
in
{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  _module.args = {
    inherit mkHostSecret;
    mkSparkSecret = mkHostSecret "spark";
  };

  # Derive the host's age identity from its ed25519 SSH host key instead
  # of a standalone age key. `/etc/ssh/ssh_host_ed25519_key` already
  # exists after first boot and has appropriate permissions, so no extra
  # key material has to be managed. The matching public-key side is
  # recorded in `.sops.yaml` at the repo root so new secrets encrypt for
  # this host automatically.
  sops.age = {
    sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    generateKey = false;
  };
}
