{ mkSparkSecret, ... }:
{
  sops.secrets."barrett-forgejo-runner-token" = mkSparkSecret "barrett-forgejo-runner-token" {
    owner = "barrett";
    mode = "0400";
  };
}
