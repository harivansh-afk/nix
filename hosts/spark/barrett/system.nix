{ ... }:
{
  # All sops.secrets declarations are centralized in
  # secrets/registry.nix + modules/security/sops.nix.
  # Consumers reference config.sops.secrets."barrett-forgejo-runner-token".path
  # directly.
}
