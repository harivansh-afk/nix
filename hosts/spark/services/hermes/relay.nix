{ config, pkgs, ... }:
{
  services.hermes-agent = {
    extraPlugins = [
      (pkgs.fetchFromGitHub {
        name = "relay-hermes";
        owner = "harivansh-afk";
        repo = "Relay-Hermes";
        rev = "15ba776994be3c53edb66b9e84958e97247fab75";
        hash = "sha256-W7HnUKFw51fyNF74F0efqXtFxgSXqcj5RWmzFVty4XA=";
      })
    ];
    environmentFiles = [ config.sops.secrets."hermes-relay.env".path ];
    settings = {
      platform_toolsets.relayapp = config.services.hermes-agent.settings.platform_toolsets.photon;
    };
  };
}
